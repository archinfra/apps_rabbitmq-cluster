#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="aict"
RELEASE="rabbitmq-cluster"
TARGET_SERIES="4.3"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/rabbitmq-upgrade-preflight.sh [options]

Options:
  -n, --namespace <ns>       Namespace, default: aict
  --release-name <name>      Helm release name, default: rabbitmq-cluster
  --target-series <series>   Target RabbitMQ series: 4.2 or 4.3, default: 4.3
  -h, --help                 Show this help

The command is read-only. It fails closed unless the current cluster is healthy,
all stable feature flags are enabled, and the requested series transition is
supported. For 4.3 it additionally requires khepri_db to be enabled before the
upgrade so metadata migration is not deferred to the first 4.3 boot.
EOF
}

die() { echo "[ERROR] $*" >&2; exit 1; }
log() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) [[ $# -ge 2 ]] || die "missing value for $1"; NAMESPACE="$2"; shift 2 ;;
    --release-name) [[ $# -ge 2 ]] || die "missing value for $1"; RELEASE="$2"; shift 2 ;;
    --target-series) [[ $# -ge 2 ]] || die "missing value for $1"; TARGET_SERIES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "${TARGET_SERIES}" in 4.2|4.3) ;; *) die "--target-series must be 4.2 or 4.3" ;; esac
for bin in kubectl awk grep sed; do command -v "$bin" >/dev/null 2>&1 || die "$bin is required"; done

selector="app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=rabbitmq"
sts="$(kubectl get sts -n "${NAMESPACE}" -l "${selector}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "${sts}" ]] || die "RabbitMQ StatefulSet not found for release ${RELEASE} in namespace ${NAMESPACE}"

expected="$(kubectl get sts "${sts}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"
ready="$(kubectl get sts "${sts}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')"
ready="${ready:-0}"
[[ "${ready}" == "${expected}" ]] || die "cluster is not fully ready: ${ready}/${expected} replicas"

pod="$(kubectl get pod -n "${NAMESPACE}" -l "${selector}" -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1)"
[[ -n "${pod}" ]] || die "no running RabbitMQ pod found"

exec_rmq() { kubectl exec -n "${NAMESPACE}" "${pod}" -- "$@"; }

version="$(exec_rmq rabbitmqctl version | tr -d '\r' | tail -n1)"
series="$(sed -E 's/^([0-9]+\.[0-9]+).*/\1/' <<<"${version}")"
log "Current RabbitMQ version: ${version}"
log "Requested target series: ${TARGET_SERIES}"

case "${TARGET_SERIES}:${series}" in
  4.2:4.1|4.2:4.0|4.2:3.13) ;;
  4.2:4.2) log "Cluster is already on RabbitMQ 4.2.x; validating readiness for patch-level maintenance." ;;
  4.3:4.2) ;;
  4.3:4.3) log "Cluster is already on RabbitMQ 4.3.x; validating readiness for patch-level maintenance." ;;
  *) die "unsupported RabbitMQ series transition ${series} -> ${TARGET_SERIES}; do not skip release series" ;;
esac

exec_rmq rabbitmq-diagnostics -q ping >/dev/null
exec_rmq rabbitmq-diagnostics -q check_running >/dev/null
exec_rmq rabbitmq-diagnostics -q check_local_alarms >/dev/null
ok "node health and local alarms"

cluster_status="$(exec_rmq rabbitmqctl cluster_status)"
if grep -qiE 'partitions[^\n]*\[[^]]+\]' <<<"${cluster_status}"; then
  echo "${cluster_status}" >&2
  die "cluster reports a network partition"
fi
ok "cluster status"

# A rolling restart must not take a node down when it would break quorum.
for p in $(kubectl get pod -n "${NAMESPACE}" -l "${selector}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort); do
  kubectl exec -n "${NAMESPACE}" "${p}" -- rabbitmq-diagnostics -q check_if_node_is_quorum_critical >/dev/null \
    || die "${p} is quorum-critical; restore quorum before upgrading"
done
ok "all nodes can be stopped one at a time without losing quorum"

flags="$(exec_rmq rabbitmqctl list_feature_flags name state | tr -d '\r')"
printf '%s\n' "${flags}"
if awk 'NF >= 2 && $2 == "disabled" {bad=1} END {exit bad ? 0 : 1}' <<<"${flags}"; then
  die "one or more feature flags are disabled; run 'rabbitmqctl enable_feature_flag all' after validating application compatibility, then rerun preflight"
fi
ok "all reported feature flags are enabled"

if [[ "${TARGET_SERIES}" == "4.3" && "${series}" == "4.2" ]]; then
  if ! awk '$1 == "khepri_db" && $2 == "enabled" {found=1} END {exit found ? 0 : 1}' <<<"${flags}"; then
    die "khepri_db is not enabled. Enable Khepri on the healthy 4.2 cluster before upgrading to 4.3"
  fi
  ok "khepri_db enabled before 4.3 upgrade"
fi

community_plugins="$(exec_rmq rabbitmq-plugins list -e -m 2>/dev/null | grep -v '^rabbitmq_' || true)"
if [[ -n "${community_plugins}" ]]; then
  echo "[WARN] Enabled non-core/community plugins detected; verify target-version compatibility manually:" >&2
  printf '%s\n' "${community_plugins}" >&2
fi

cat <<EOF

Upgrade preflight: PASS
  release:        ${RELEASE}
  namespace:      ${NAMESPACE}
  current:        ${version}
  target series:  ${TARGET_SERIES}

This check does not mutate the cluster. Continue only after backup/definitions
export and application-level validation are complete.
EOF
