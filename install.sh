#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

APP_NAME="rabbitmq-cluster"
APP_VERSION="0.2.0"
PACKAGE_PROFILE="integrated"
WORKDIR="/tmp/${APP_NAME}-installer"
CHART_DIR="${WORKDIR}/charts/rabbitmq"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"
SCRIPTS_DIR="${WORKDIR}/scripts"
UPGRADE_PREFLIGHT="${SCRIPTS_DIR}/rabbitmq-upgrade-preflight.sh"

ACTION="help"
RELEASE_NAME="rabbitmq-cluster"
NAMESPACE="aict"
TARGET_SERIES="4.3"
RABBITMQ_REPLICAS="3"
RABBITMQ_USERNAME="admin"
RABBITMQ_PASSWORD=""
RABBITMQ_PASSWORD_FILE=""
RABBITMQ_ERLANG_COOKIE=""
RABBITMQ_ERLANG_COOKIE_FILE=""
RABBITMQ_SECRET_NAME=""
RABBITMQ_PASSWORD_KEY="rabbitmq-password"
RABBITMQ_ERLANG_COOKIE_KEY="rabbitmq-erlang-cookie"
ROTATE_PASSWORD="false"
ROTATE_ERLANG_COOKIE="false"
SECRET_IS_EXTERNAL="false"
STORAGE_CLASS="nfs"
STORAGE_SIZE="20Gi"
SERVICE_TYPE="ClusterIP"
AMQP_NODE_PORT="30672"
MANAGER_NODE_PORT="31672"
RESOURCE_PROFILE="mid"
IMAGE_PULL_POLICY="IfNotPresent"
WAIT_TIMEOUT="10m"
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
REGISTRY_USER=""
REGISTRY_PASS=""
REGISTRY_PASS_FILE=""
SKIP_IMAGE_PREPARE="false"
DELETE_PVC="false"
ENABLE_METRICS="true"
ENABLE_SERVICEMONITOR="true"
ENABLE_PROMETHEUSRULE="true"
SERVICE_MONITOR_NAMESPACE=""
SERVICE_MONITOR_INTERVAL="30s"
SERVICE_MONITOR_SCRAPE_TIMEOUT=""
AUTO_YES="false"
COOKIE_ROTATION_DOWNTIME="false"

HELM_ARGS=()
RESOURCE_HELM_ARGS=()

declare -A IMAGE_DEFAULT_TARGETS=()
declare -A IMAGE_EFFECTIVE_TARGETS=()
declare -A IMAGE_LOAD_REFS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo; echo -e "${BLUE}${BOLD}============================================================${NC}"; echo -e "${BLUE}${BOLD}$*${NC}"; echo -e "${BLUE}${BOLD}============================================================${NC}"; }
program_name() { basename "$0"; }

banner() {
  echo
  echo -e "${GREEN}${BOLD}RabbitMQ Cluster Offline Installer${NC}"
  echo -e "${CYAN}Version: ${APP_VERSION}${NC}"
  echo -e "${CYAN}Package: ${PACKAGE_PROFILE}${NC}"
}

usage() {
  local cmd="./$(program_name)"
  cat <<EOF
Usage:
  ${cmd} <install|preflight|uninstall|status|help> [options] [-- <helm_args>]
  ${cmd} -h|--help

Actions:
  install       Prepare images and install or upgrade a RabbitMQ 4.3 cluster
  preflight     Read-only in-place upgrade readiness check for RabbitMQ 4.2/4.3
  uninstall     Uninstall the RabbitMQ release
  status        Show Helm and Kubernetes resource status
  help          Show this message

Core options:
  -n, --namespace <ns>                 Namespace, default: ${NAMESPACE}
  --release-name <name>                Helm release name, default: ${RELEASE_NAME}
  --target-series <series>             Preflight target series: 4.2|4.3, default: ${TARGET_SERIES}
  --replicas <num>                     Odd production replica count >=3, default: ${RABBITMQ_REPLICAS}
  --username <name>                    RabbitMQ application username, default: ${RABBITMQ_USERNAME}
  --storage-class <name>               StorageClass, default: ${STORAGE_CLASS} (compatibility default)
  --storage-size <size>                PVC size, default: ${STORAGE_SIZE}
  --service-type <type>                ClusterIP|NodePort|LoadBalancer, default: ${SERVICE_TYPE}
  --amqp-node-port <port>              AMQP NodePort, default: ${AMQP_NODE_PORT}
  --manager-node-port <port>           Management NodePort, default: ${MANAGER_NODE_PORT}
  --resource-profile <name>            low|mid|midd|high, default: ${RESOURCE_PROFILE}

Authentication:
  --existing-secret <name>             Use an existing Secret containing password and Erlang cookie
  --secret-password-key <key>          Password key, default: ${RABBITMQ_PASSWORD_KEY}
  --secret-erlang-cookie-key <key>     Erlang cookie key, default: ${RABBITMQ_ERLANG_COOKIE_KEY}
  --password-file <path>               Seed/rotate managed RabbitMQ password from a file
  --password <pwd>                     Compatibility input; may remain in shell history
  --erlang-cookie-file <path>          Seed/rotate managed Erlang cookie from a file
  --erlang-cookie <value>              Compatibility input; may remain in shell history
  --rotate-password                    Rotate the managed RabbitMQ password
  --rotate-erlang-cookie               Rotate the managed Erlang cookie; requires full-cluster restart/downtime

  First install creates ${RELEASE_NAME}-auth with random credentials when no existing
  Secret or input files are provided. Managed credentials are reused on upgrade.
  Existing Bitnami credentials are copied into the archinfra managed Secret before a
  series upgrade, so an upgrade never silently rotates the Erlang cookie.
  Password and Erlang cookie values are never passed through Helm CLI values.

Monitoring:
  --enable-metrics / --disable-metrics
  --enable-servicemonitor / --disable-servicemonitor
  --enable-prometheusrule / --disable-prometheusrule
  --service-monitor-namespace <ns>
  --service-monitor-interval <value>   Default: ${SERVICE_MONITOR_INTERVAL}
  --service-monitor-scrape-timeout <value>

Image and rollout:
  --registry <repo-prefix>             Target image repo prefix, default: ${REGISTRY_REPO}
  --registry-user <user>               Optional registry username; omitted reuses Docker credentials
  --registry-password-file <path>      Registry password file (recommended)
  --registry-password <password>       Compatibility input; may remain in shell history
  --image-pull-policy <policy>         Always|IfNotPresent|Never, default: ${IMAGE_PULL_POLICY}
  --skip-image-prepare                 Reuse images already available in the target registry
  --wait-timeout <duration>            Helm/kubectl wait timeout, default: ${WAIT_TIMEOUT}

Other:
  --delete-pvc                         With uninstall, also delete release PVCs
  -y, --yes                            Skip confirmation
  -h, --help                           Show help

Examples:
  ${cmd} install -y
  ${cmd} install --password-file /secure/rabbitmq.password -y
  ${cmd} install --existing-secret rabbitmq-prod-auth -y
  ${cmd} install --resource-profile high --storage-class fast-block -y
  ${cmd} install --registry harbor.example.com/kube4 --registry-user robot --registry-password-file /secure/harbor.password -y
  ${cmd} preflight --target-series 4.3 -n ${NAMESPACE}
  ${cmd} status -n ${NAMESPACE}
  ${cmd} uninstall --delete-pvc -y
EOF
}

cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

parse_args() {
  if [[ $# -eq 0 ]]; then ACTION="help"; return; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|preflight|uninstall|status|help) ACTION="$1"; shift ;;
      -n|--namespace) [[ $# -ge 2 ]] || die "Missing value for $1"; NAMESPACE="$2"; shift 2 ;;
      --release-name) [[ $# -ge 2 ]] || die "Missing value for $1"; RELEASE_NAME="$2"; shift 2 ;;
      --target-series) [[ $# -ge 2 ]] || die "Missing value for $1"; TARGET_SERIES="$2"; shift 2 ;;
      --replicas) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_REPLICAS="$2"; shift 2 ;;
      --username) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_USERNAME="$2"; shift 2 ;;
      --password) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_PASSWORD="$2"; shift 2 ;;
      --password-file) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_PASSWORD_FILE="$2"; shift 2 ;;
      --erlang-cookie) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_ERLANG_COOKIE="$2"; shift 2 ;;
      --erlang-cookie-file) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_ERLANG_COOKIE_FILE="$2"; shift 2 ;;
      --existing-secret) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_SECRET_NAME="$2"; SECRET_IS_EXTERNAL="true"; shift 2 ;;
      --secret-password-key) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_PASSWORD_KEY="$2"; shift 2 ;;
      --secret-erlang-cookie-key) [[ $# -ge 2 ]] || die "Missing value for $1"; RABBITMQ_ERLANG_COOKIE_KEY="$2"; shift 2 ;;
      --rotate-password) ROTATE_PASSWORD="true"; shift ;;
      --rotate-erlang-cookie) ROTATE_ERLANG_COOKIE="true"; shift ;;
      --storage-class) [[ $# -ge 2 ]] || die "Missing value for $1"; STORAGE_CLASS="$2"; shift 2 ;;
      --storage-size) [[ $# -ge 2 ]] || die "Missing value for $1"; STORAGE_SIZE="$2"; shift 2 ;;
      --service-type) [[ $# -ge 2 ]] || die "Missing value for $1"; SERVICE_TYPE="$2"; shift 2 ;;
      --amqp-node-port) [[ $# -ge 2 ]] || die "Missing value for $1"; AMQP_NODE_PORT="$2"; shift 2 ;;
      --manager-node-port) [[ $# -ge 2 ]] || die "Missing value for $1"; MANAGER_NODE_PORT="$2"; shift 2 ;;
      --resource-profile) [[ $# -ge 2 ]] || die "Missing value for $1"; RESOURCE_PROFILE="$2"; shift 2 ;;
      --enable-metrics) ENABLE_METRICS="true"; shift ;;
      --disable-metrics) ENABLE_METRICS="false"; shift ;;
      --enable-servicemonitor) ENABLE_SERVICEMONITOR="true"; shift ;;
      --disable-servicemonitor) ENABLE_SERVICEMONITOR="false"; shift ;;
      --enable-prometheusrule) ENABLE_PROMETHEUSRULE="true"; shift ;;
      --disable-prometheusrule) ENABLE_PROMETHEUSRULE="false"; shift ;;
      --service-monitor-namespace) [[ $# -ge 2 ]] || die "Missing value for $1"; SERVICE_MONITOR_NAMESPACE="$2"; shift 2 ;;
      --service-monitor-interval) [[ $# -ge 2 ]] || die "Missing value for $1"; SERVICE_MONITOR_INTERVAL="$2"; shift 2 ;;
      --service-monitor-scrape-timeout) [[ $# -ge 2 ]] || die "Missing value for $1"; SERVICE_MONITOR_SCRAPE_TIMEOUT="$2"; shift 2 ;;
      --registry) [[ $# -ge 2 ]] || die "Missing value for $1"; REGISTRY_REPO="$2"; REGISTRY_REPO_EXPLICIT="true"; shift 2 ;;
      --registry-user) [[ $# -ge 2 ]] || die "Missing value for $1"; REGISTRY_USER="$2"; shift 2 ;;
      --registry-password) [[ $# -ge 2 ]] || die "Missing value for $1"; REGISTRY_PASS="$2"; shift 2 ;;
      --registry-password-file) [[ $# -ge 2 ]] || die "Missing value for $1"; REGISTRY_PASS_FILE="$2"; shift 2 ;;
      --image-pull-policy) [[ $# -ge 2 ]] || die "Missing value for $1"; IMAGE_PULL_POLICY="$2"; shift 2 ;;
      --skip-image-prepare) SKIP_IMAGE_PREPARE="true"; shift ;;
      --wait-timeout) [[ $# -ge 2 ]] || die "Missing value for $1"; WAIT_TIMEOUT="$2"; shift 2 ;;
      --delete-pvc) DELETE_PVC="true"; shift ;;
      -y|--yes) AUTO_YES="true"; shift ;;
      -h|--help) ACTION="help"; shift ;;
      --) shift; while [[ $# -gt 0 ]]; do HELM_ARGS+=("$1"); shift; done; break ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

is_valid_nodeport() { [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 30000 && "$1" <= 32767 )); }

normalize_flags() {
  case "${TARGET_SERIES}" in 4.2|4.3) ;; *) die "--target-series must be 4.2 or 4.3" ;; esac
  case "${SERVICE_TYPE}" in ClusterIP|NodePort|LoadBalancer) ;; *) die "Unsupported service type: ${SERVICE_TYPE}" ;; esac
  case "${IMAGE_PULL_POLICY}" in Always|IfNotPresent|Never) ;; *) die "Unsupported image pull policy: ${IMAGE_PULL_POLICY}" ;; esac
  [[ "${RABBITMQ_REPLICAS}" =~ ^[0-9]+$ ]] || die "--replicas must be an integer"
  if [[ "${ACTION}" == "install" ]]; then
    (( RABBITMQ_REPLICAS >= 3 )) || die "production RabbitMQ requires at least 3 replicas"
    (( RABBITMQ_REPLICAS % 2 == 1 )) || die "production RabbitMQ replica count must be odd (3, 5, ...)"
  fi

  if [[ "${ENABLE_SERVICEMONITOR}" == "true" || "${ENABLE_PROMETHEUSRULE}" == "true" ]]; then ENABLE_METRICS="true"; fi
  case "${RESOURCE_PROFILE,,}" in
    low) RESOURCE_PROFILE="low" ;;
    mid|midd|middle|medium) RESOURCE_PROFILE="mid" ;;
    high) RESOURCE_PROFILE="high" ;;
    *) die "Unsupported resource profile: ${RESOURCE_PROFILE}. Expected low|mid|midd|high" ;;
  esac
  if [[ "${SERVICE_TYPE}" == "NodePort" || "${SERVICE_TYPE}" == "LoadBalancer" ]]; then
    is_valid_nodeport "${AMQP_NODE_PORT}" || die "AMQP NodePort must be 30000-32767"
    is_valid_nodeport "${MANAGER_NODE_PORT}" || die "Management NodePort must be 30000-32767"
  fi

  [[ -z "${RABBITMQ_PASSWORD}" || -z "${RABBITMQ_PASSWORD_FILE}" ]] || die "Use only one of --password or --password-file"
  [[ -z "${RABBITMQ_ERLANG_COOKIE}" || -z "${RABBITMQ_ERLANG_COOKIE_FILE}" ]] || die "Use only one of --erlang-cookie or --erlang-cookie-file"
  if [[ "${SECRET_IS_EXTERNAL}" == "true" ]]; then
    [[ -z "${RABBITMQ_PASSWORD}" && -z "${RABBITMQ_PASSWORD_FILE}" && -z "${RABBITMQ_ERLANG_COOKIE}" && -z "${RABBITMQ_ERLANG_COOKIE_FILE}" ]] || die "--existing-secret cannot be combined with credential input"
    [[ "${ROTATE_PASSWORD}" == "false" && "${ROTATE_ERLANG_COOKIE}" == "false" ]] || die "Installer cannot rotate an externally managed Secret"
  elif [[ -z "${RABBITMQ_SECRET_NAME}" ]]; then
    RABBITMQ_SECRET_NAME="${RELEASE_NAME}-auth"
  fi

  [[ -z "${REGISTRY_PASS}" || -z "${REGISTRY_PASS_FILE}" ]] || die "Use only one of --registry-password or --registry-password-file"
  [[ -z "${REGISTRY_PASS_FILE}" || -r "${REGISTRY_PASS_FILE}" ]] || die "Registry password file is not readable: ${REGISTRY_PASS_FILE}"
  if [[ -n "${REGISTRY_USER}" && -z "${REGISTRY_PASS}" && -z "${REGISTRY_PASS_FILE}" ]]; then die "--registry-user requires registry password input"; fi
  if [[ -z "${REGISTRY_USER}" && ( -n "${REGISTRY_PASS}" || -n "${REGISTRY_PASS_FILE}" ) ]]; then die "Registry password requires --registry-user"; fi

  local arg lower
  for arg in "${HELM_ARGS[@]}"; do
    lower="${arg,,}"
    if [[ "${lower}" == *"auth.password"* || "${lower}" == *"auth.erlangcookie"* || "${lower}" == *"auth.existingpasswordsecret"* || "${lower}" == *"auth.existingerlangsecret"* || "${lower}" == *"auth.existingsecretpasswordkey"* || "${lower}" == *"auth.existingsecreterlangkey"* || "${lower}" == *"usepasswordfiles"* || "${lower}" == *"rabbitmq-password="* || "${lower}" == *"rabbitmq-erlang-cookie="* ]]; then
      die "Do not override RabbitMQ credential/Secret settings through Helm extra args; use Secret-oriented installer options"
    fi
  done
}

check_deps() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  case "${ACTION}" in
    install|uninstall|status) command -v helm >/dev/null 2>&1 || die "helm is required" ;;
  esac
  if [[ "${ACTION}" == "install" ]]; then
    command -v base64 >/dev/null 2>&1 || die "base64 is required"
    if [[ "${SKIP_IMAGE_PREPARE}" != "true" ]]; then command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"; fi
  fi
}

validate_storage_policy() {
  [[ "${ACTION}" == "install" ]] || return 0
  if [[ "${STORAGE_CLASS,,}" == *nfs* ]]; then
    warn "StorageClass '${STORAGE_CLASS}' is the archinfra compatibility default, not the preferred RabbitMQ production storage."
    warn "For durable Quorum Queues/Streams prefer low-latency block storage or local SSD/NVMe with tested failure semantics."
  fi
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return 0
  section "Deployment Plan"
  echo "Action                  : ${ACTION}"
  echo "Release                 : ${RELEASE_NAME}"
  echo "Namespace               : ${NAMESPACE}"
  if [[ "${ACTION}" == "install" ]]; then
    echo "Replicas                : ${RABBITMQ_REPLICAS}"
    echo "Username                : ${RABBITMQ_USERNAME}"
    echo "Auth Secret             : ${RABBITMQ_SECRET_NAME}"
    echo "Rotate password         : ${ROTATE_PASSWORD}"
    echo "Rotate Erlang cookie    : ${ROTATE_ERLANG_COOKIE}"
    echo "StorageClass            : ${STORAGE_CLASS}"
    echo "Storage size            : ${STORAGE_SIZE}"
    echo "Resource profile        : ${RESOURCE_PROFILE}"
    echo "Service type            : ${SERVICE_TYPE}"
    echo "Metrics                 : ${ENABLE_METRICS}"
    echo "ServiceMonitor          : ${ENABLE_SERVICEMONITOR}"
    echo "PrometheusRule          : ${ENABLE_PROMETHEUSRULE}"
    echo "Registry repo           : ${REGISTRY_REPO}"
    echo "Skip image prepare      : ${SKIP_IMAGE_PREPARE}"
    [[ "${ROTATE_ERLANG_COOKIE}" == "true" ]] && warn "Erlang cookie rotation causes a full RabbitMQ cluster restart and downtime."
  fi
  if [[ "${ACTION}" == "uninstall" ]]; then echo "Delete PVC              : ${DELETE_PVC}"; fi
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "Cancelled"
}

payload_start_offset() {
  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || die "Unable to locate embedded payload"
  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"
  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in 0a|0d) skip_bytes=$((skip_bytes + 1)) ;; "") die "Installer payload boundary is invalid" ;; *) break ;; esac
  done
  printf '%s' "$((payload_offset + skip_bytes))"
}

extract_payload() {
  local payload_offset
  payload_offset="$(payload_start_offset)"
  rm -rf "${WORKDIR}"; mkdir -p "${WORKDIR}"
  tail -c +"${payload_offset}" "$0" | tar -xz -C "${WORKDIR}" || die "failed to extract payload"
  [[ -d "${CHART_DIR}" ]] || die "Missing chart payload"
  [[ -f "${CHART_DIR}/values-archinfra.yaml" ]] || die "Missing archinfra production values"
  [[ -f "${IMAGE_INDEX}" ]] || die "Missing image metadata payload"
  [[ -f "${UPGRADE_PREFLIGHT}" ]] || die "Missing RabbitMQ upgrade preflight payload"
}

image_name_from_ref() { local ref="$1" name_tag="${ref##*/}"; echo "${name_tag%%:*}"; }
image_name_tag_from_ref() { local ref="$1"; echo "${ref##*/}"; }
resolve_target_ref() { local ref="$1"; [[ "${REGISTRY_REPO_EXPLICIT}" == "true" ]] && echo "${REGISTRY_REPO}/$(image_name_tag_from_ref "${ref}")" || echo "${ref}"; }
image_registry_from_ref() { local ref="$1"; echo "${ref%%/*}"; }
image_repository_from_ref() { local ref="$1" remainder="${ref#*/}"; echo "${remainder%:*}"; }
image_tag_from_ref() { local ref="$1"; echo "${ref##*:}"; }

load_image_metadata() {
  while IFS=$'\t' read -r tar_name load_ref default_target_ref _platform; do
    [[ -n "${tar_name}" ]] || continue
    IMAGE_LOAD_REFS["${tar_name}"]="${load_ref}"
    IMAGE_DEFAULT_TARGETS["${tar_name}"]="${default_target_ref}"
    IMAGE_EFFECTIVE_TARGETS["${tar_name}"]="$(resolve_target_ref "${default_target_ref}")"
  done < "${IMAGE_INDEX}"
}

find_image_ref_by_name() {
  local wanted="$1" tar_name
  for tar_name in "${!IMAGE_EFFECTIVE_TARGETS[@]}"; do
    [[ "$(image_name_from_ref "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}")" == "${wanted}" ]] && { echo "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"; return 0; }
  done
  return 1
}

docker_login() {
  local registry_host="${REGISTRY_REPO%%/*}" password=""
  if [[ -z "${REGISTRY_USER}" ]]; then log "Using existing Docker credentials for ${registry_host}"; return 0; fi
  if [[ -n "${REGISTRY_PASS_FILE}" ]]; then password="$(cat "${REGISTRY_PASS_FILE}")"; else password="${REGISTRY_PASS}"; fi
  printf '%s' "${password}" | docker login "${registry_host}" -u "${REGISTRY_USER}" --password-stdin >/dev/null 2>&1 || die "docker login failed for ${registry_host}"
  unset password
}

prepare_images() {
  [[ "${SKIP_IMAGE_PREPARE}" == "true" ]] && { log "Skipping image prepare"; return 0; }
  docker_login
  local tar_name load_ref default_target_ref target_ref tar_path _platform
  while IFS=$'\t' read -r tar_name load_ref default_target_ref _platform; do
    [[ -n "${tar_name}" ]] || continue
    tar_path="${IMAGE_DIR}/${tar_name}"; [[ -f "${tar_path}" ]] || die "Missing image tar: ${tar_path}"
    target_ref="${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"
    log "Loading ${tar_name}"; docker load -i "${tar_path}" >/dev/null
    [[ "${load_ref}" == "${target_ref}" ]] || docker tag "${load_ref}" "${target_ref}"
    log "Pushing ${target_ref}"; docker push "${target_ref}" >/dev/null
  done < "${IMAGE_INDEX}"
  success "Image prepare completed"
}

ensure_namespace() { kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}" >/dev/null; }
secret_has_key() { local name="$1" key="$2" value; value="$(kubectl get secret "${name}" -n "${NAMESPACE}" -o "go-template={{ index .data \"${key}\" }}" 2>/dev/null || true)"; [[ -n "${value}" ]]; }
secret_key_to_file() { local name="$1" key="$2" out="$3"; kubectl get secret "${name}" -n "${NAMESPACE}" -o "go-template={{ index .data \"${key}\" }}" | base64 -d > "${out}"; chmod 0600 "${out}"; }

generate_random_file() {
  local output="$1" length="$2" raw=""
  while (( ${#raw} < length )); do raw+="$(head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | tr -d '\n')"; done
  printf '%s' "${raw:0:length}" > "${output}"; chmod 0600 "${output}"
}

prepare_credential_file() {
  local output="$1" supplied_file="$2" supplied_value="$3" length="$4"
  if [[ -n "${supplied_file}" ]]; then [[ -r "${supplied_file}" ]] || die "Credential file is not readable: ${supplied_file}"; cat "${supplied_file}" > "${output}"
  elif [[ -n "${supplied_value}" ]]; then printf '%s' "${supplied_value}" > "${output}"
  else generate_random_file "${output}" "${length}"
  fi
  [[ -s "${output}" ]] || die "Credential must not be empty"; chmod 0600 "${output}"
}

release_exists() { helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; }

stop_cluster_for_cookie_rotation() {
  release_exists || return 0
  local sts
  sts="$(kubectl get sts -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${sts}" ]] || die "Unable to locate RabbitMQ StatefulSet for safe Erlang cookie rotation"
  warn "Scaling ${sts} to 0 before Erlang cookie rotation; RabbitMQ will be unavailable."
  kubectl scale statefulset "${sts}" -n "${NAMESPACE}" --replicas=0 >/dev/null
  kubectl wait --for=delete pod -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" --timeout="${WAIT_TIMEOUT}" >/dev/null || die "Timed out waiting for RabbitMQ pods to stop"
  COOKIE_ROTATION_DOWNTIME="true"
}

current_auth_secret_candidates() {
  local sts
  sts="$(kubectl get sts -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${sts}" ]] || return 0
  kubectl get sts "${sts}" -n "${NAMESPACE}" -o go-template='{{range .spec.template.spec.volumes}}{{if eq .name "rabbitmq-secrets"}}{{range .projected.sources}}{{if .secret}}{{.secret.name}}{{"\n"}}{{end}}{{end}}{{end}}{{end}}' 2>/dev/null || true
  kubectl get secret -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/name=rabbitmq" -o name 2>/dev/null | sed 's#^secret/##' || true
}

find_unique_secret_for_key() {
  local key="$1" candidate found=""
  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    if secret_has_key "${candidate}" "${key}"; then
      if [[ -n "${found}" && "${found}" != "${candidate}" ]]; then
        die "Multiple existing Secrets contain ${key}; use --existing-secret explicitly"
      fi
      found="${candidate}"
    fi
  done < <(current_auth_secret_candidates | sort -u)
  [[ -n "${found}" ]] || return 1
  printf '%s' "${found}"
}

migrate_existing_auth_secret_if_needed() {
  [[ "${SECRET_IS_EXTERNAL}" == "false" ]] || return 0
  release_exists || return 0
  kubectl get secret "${RABBITMQ_SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1 && return 0

  local password_source cookie_source password_file cookie_file
  password_source="$(find_unique_secret_for_key "${RABBITMQ_PASSWORD_KEY}" || true)"
  cookie_source="$(find_unique_secret_for_key "${RABBITMQ_ERLANG_COOKIE_KEY}" || true)"
  [[ -n "${password_source}" && -n "${cookie_source}" ]] || die "Existing RabbitMQ release found but current credentials could not be identified safely. Re-run with --existing-secret <name>."

  password_file="${WORKDIR}/.migrated-rabbitmq-password"
  cookie_file="${WORKDIR}/.migrated-rabbitmq-erlang-cookie"
  secret_key_to_file "${password_source}" "${RABBITMQ_PASSWORD_KEY}" "${password_file}"
  secret_key_to_file "${cookie_source}" "${RABBITMQ_ERLANG_COOKIE_KEY}" "${cookie_file}"
  kubectl create secret generic "${RABBITMQ_SECRET_NAME}" -n "${NAMESPACE}" \
    --from-file="${RABBITMQ_PASSWORD_KEY}=${password_file}" \
    --from-file="${RABBITMQ_ERLANG_COOKIE_KEY}=${cookie_file}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  rm -f "${password_file}" "${cookie_file}"
  kubectl label secret "${RABBITMQ_SECRET_NAME}" -n "${NAMESPACE}" \
    app.kubernetes.io/managed-by=archinfra app.kubernetes.io/instance="${RELEASE_NAME}" app.kubernetes.io/name=rabbitmq --overwrite >/dev/null
  success "Copied existing RabbitMQ password/cookie into managed Secret ${RABBITMQ_SECRET_NAME} without rotation"
}

ensure_auth_secret() {
  ensure_namespace
  if [[ "${SECRET_IS_EXTERNAL}" == "true" ]]; then
    kubectl get secret "${RABBITMQ_SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1 || die "Existing Secret not found: ${NAMESPACE}/${RABBITMQ_SECRET_NAME}"
    secret_has_key "${RABBITMQ_SECRET_NAME}" "${RABBITMQ_PASSWORD_KEY}" || die "Secret is missing ${RABBITMQ_PASSWORD_KEY}"
    secret_has_key "${RABBITMQ_SECRET_NAME}" "${RABBITMQ_ERLANG_COOKIE_KEY}" || die "Secret is missing ${RABBITMQ_ERLANG_COOKIE_KEY}"
    success "Using external RabbitMQ Secret ${RABBITMQ_SECRET_NAME}"
    return 0
  fi

  migrate_existing_auth_secret_if_needed

  local password_file="${WORKDIR}/.rabbitmq-password" cookie_file="${WORKDIR}/.rabbitmq-erlang-cookie"
  local exists="false"
  if kubectl get secret "${RABBITMQ_SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then exists="true"; fi

  if [[ "${exists}" == "true" ]]; then
    secret_has_key "${RABBITMQ_SECRET_NAME}" "${RABBITMQ_PASSWORD_KEY}" || die "Managed Secret is missing ${RABBITMQ_PASSWORD_KEY}"
    secret_has_key "${RABBITMQ_SECRET_NAME}" "${RABBITMQ_ERLANG_COOKIE_KEY}" || die "Managed Secret is missing ${RABBITMQ_ERLANG_COOKIE_KEY}"
    if [[ "${ROTATE_PASSWORD}" == "false" && ( -n "${RABBITMQ_PASSWORD}" || -n "${RABBITMQ_PASSWORD_FILE}" ) ]]; then die "Existing Secret is reused on upgrade; add --rotate-password to change it"; fi
    if [[ "${ROTATE_ERLANG_COOKIE}" == "false" && ( -n "${RABBITMQ_ERLANG_COOKIE}" || -n "${RABBITMQ_ERLANG_COOKIE_FILE}" ) ]]; then die "Existing Erlang cookie is reused; add --rotate-erlang-cookie for a coordinated restart"; fi
    if [[ "${ROTATE_PASSWORD}" == "false" && "${ROTATE_ERLANG_COOKIE}" == "false" ]]; then success "Reusing RabbitMQ authentication Secret ${RABBITMQ_SECRET_NAME}"; return 0; fi

    [[ "${ROTATE_ERLANG_COOKIE}" == "true" ]] && stop_cluster_for_cookie_rotation
    if [[ "${ROTATE_PASSWORD}" == "true" ]]; then prepare_credential_file "${password_file}" "${RABBITMQ_PASSWORD_FILE}" "${RABBITMQ_PASSWORD}" 48; else secret_key_to_file "${RABBITMQ_SECRET_NAME}" "${RABBITMQ_PASSWORD_KEY}" "${password_file}"; fi
    if [[ "${ROTATE_ERLANG_COOKIE}" == "true" ]]; then prepare_credential_file "${cookie_file}" "${RABBITMQ_ERLANG_COOKIE_FILE}" "${RABBITMQ_ERLANG_COOKIE}" 48; else secret_key_to_file "${RABBITMQ_SECRET_NAME}" "${RABBITMQ_ERLANG_COOKIE_KEY}" "${cookie_file}"; fi
  else
    prepare_credential_file "${password_file}" "${RABBITMQ_PASSWORD_FILE}" "${RABBITMQ_PASSWORD}" 48
    prepare_credential_file "${cookie_file}" "${RABBITMQ_ERLANG_COOKIE_FILE}" "${RABBITMQ_ERLANG_COOKIE}" 48
  fi

  kubectl create secret generic "${RABBITMQ_SECRET_NAME}" -n "${NAMESPACE}" \
    --from-file="${RABBITMQ_PASSWORD_KEY}=${password_file}" \
    --from-file="${RABBITMQ_ERLANG_COOKIE_KEY}=${cookie_file}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  rm -f "${password_file}" "${cookie_file}"
  kubectl label secret "${RABBITMQ_SECRET_NAME}" -n "${NAMESPACE}" \
    app.kubernetes.io/managed-by=archinfra app.kubernetes.io/instance="${RELEASE_NAME}" app.kubernetes.io/name=rabbitmq --overwrite >/dev/null
  RABBITMQ_PASSWORD=""; RABBITMQ_ERLANG_COOKIE=""
  success "RabbitMQ authentication Secret ${RABBITMQ_SECRET_NAME} is ready"
}

run_upgrade_preflight() {
  local target="${1:-4.3}"
  [[ -f "${UPGRADE_PREFLIGHT}" ]] || die "Upgrade preflight script is missing from the offline payload"
  bash "${UPGRADE_PREFLIGHT}" -n "${NAMESPACE}" --release-name "${RELEASE_NAME}" --target-series "${target}"
}

check_existing_series_upgrade() {
  release_exists || return 0
  local existing_image
  existing_image="$(kubectl get sts -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o jsonpath='{.items[0].spec.template.spec.containers[?(@.name=="rabbitmq")].image}' 2>/dev/null || true)"
  case "${existing_image}" in
    *:4.1.*|*-4.1.*) die "Direct RabbitMQ 4.1.x -> 4.3.x upgrade is unsupported. Upgrade first to the latest 4.2.x patch (4.2.10 baseline), enable all required feature flags/Khepri, then run this 4.3 installer." ;;
    *:4.2.*|*-4.2.*)
      warn "RabbitMQ 4.2.x -> 4.3.x requires feature-flag/Khepri preflight; running read-only checks now."
      run_upgrade_preflight 4.3
      success "RabbitMQ 4.2 -> 4.3 upgrade preflight passed"
      ;;
  esac
}

check_servicemonitor_support() { [[ "${ENABLE_SERVICEMONITOR}" == "true" ]] || return 0; kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 || { warn "ServiceMonitor CRD not found; disabling ServiceMonitor"; ENABLE_SERVICEMONITOR="false"; }; }
check_prometheusrule_support() { [[ "${ENABLE_PROMETHEUSRULE}" == "true" ]] || return 0; kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1 || { warn "PrometheusRule CRD not found; disabling PrometheusRule"; ENABLE_PROMETHEUSRULE="false"; }; }

preview_command() {
  local rendered=() arg lower
  for arg in "$@"; do
    lower="${arg,,}"
    if [[ "${lower}" == *"password="* || "${lower}" == *"cookie="* || "${lower}" == *"token="* || "${lower}" == *"credential="* ]]; then rendered+=("<redacted>"); else rendered+=("$(printf '%q' "${arg}")"); fi
  done
  printf '%s ' "${rendered[@]}"; echo
}

build_resource_profile_args() {
  RESOURCE_HELM_ARGS=(--set "resourcesPreset=none" --set "volumePermissions.resourcesPreset=none" --set "memoryHighWatermark.enabled=true" --set-string "memoryHighWatermark.type=absolute")
  case "${RESOURCE_PROFILE}" in
    low)
      RESOURCE_HELM_ARGS+=(--set-string "resources.requests.cpu=250m" --set-string "resources.requests.memory=512Mi" --set-string "resources.limits.cpu=500m" --set-string "resources.limits.memory=1Gi" --set-string "memoryHighWatermark.value=640Mi" --set-string "archinfra.diskFreeLimit=1GB") ;;
    mid)
      RESOURCE_HELM_ARGS+=(--set-string "resources.requests.cpu=500m" --set-string "resources.requests.memory=1Gi" --set-string "resources.limits.cpu=1" --set-string "resources.limits.memory=2Gi" --set-string "memoryHighWatermark.value=1280Mi" --set-string "archinfra.diskFreeLimit=2GB") ;;
    high)
      RESOURCE_HELM_ARGS+=(--set-string "resources.requests.cpu=1" --set-string "resources.requests.memory=2Gi" --set-string "resources.limits.cpu=2" --set-string "resources.limits.memory=4Gi" --set-string "memoryHighWatermark.value=2560Mi" --set-string "archinfra.diskFreeLimit=4GB") ;;
  esac
}

install_release() {
  local rabbitmq_image os_shell_image
  rabbitmq_image="$(find_image_ref_by_name rabbitmq)" || die "Unable to resolve rabbitmq image"
  os_shell_image="$(find_image_ref_by_name os-shell)" || die "Unable to resolve os-shell image"
  build_resource_profile_args

  local helm_cmd=(helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" -n "${NAMESPACE}" --create-namespace --wait --timeout "${WAIT_TIMEOUT}" -f "${CHART_DIR}/values-archinfra.yaml"
    --set "replicaCount=${RABBITMQ_REPLICAS}"
    --set-string "auth.username=${RABBITMQ_USERNAME}"
    --set-string "auth.existingPasswordSecret=${RABBITMQ_SECRET_NAME}"
    --set-string "auth.existingSecretPasswordKey=${RABBITMQ_PASSWORD_KEY}"
    --set-string "auth.existingErlangSecret=${RABBITMQ_SECRET_NAME}"
    --set-string "auth.existingSecretErlangKey=${RABBITMQ_ERLANG_COOKIE_KEY}"
    --set "auth.updatePassword=${ROTATE_PASSWORD}"
    --set "usePasswordFiles=true"
    --set-string "persistence.storageClass=${STORAGE_CLASS}"
    --set-string "persistence.size=${STORAGE_SIZE}"
    --set-string "image.registry=$(image_registry_from_ref "${rabbitmq_image}")"
    --set-string "image.repository=$(image_repository_from_ref "${rabbitmq_image}")"
    --set-string "image.tag=$(image_tag_from_ref "${rabbitmq_image}")"
    --set-string "image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "volumePermissions.image.registry=$(image_registry_from_ref "${os_shell_image}")"
    --set-string "volumePermissions.image.repository=$(image_repository_from_ref "${os_shell_image}")"
    --set-string "volumePermissions.image.tag=$(image_tag_from_ref "${os_shell_image}")"
    --set-string "volumePermissions.image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "service.type=${SERVICE_TYPE}"
    --set "metrics.enabled=${ENABLE_METRICS}"
    --set "metrics.serviceMonitor.default.enabled=${ENABLE_SERVICEMONITOR}"
    --set "metrics.prometheusRule.enabled=${ENABLE_PROMETHEUSRULE}"
    --set-string "metrics.serviceMonitor.default.interval=${SERVICE_MONITOR_INTERVAL}"
    --set-string "metrics.serviceMonitor.labels.monitoring\\.archinfra\\.io/stack=default"
    --set-string "metrics.prometheusRule.additionalLabels.monitoring\\.archinfra\\.io/stack=default")

  [[ "${SERVICE_TYPE}" == "NodePort" || "${SERVICE_TYPE}" == "LoadBalancer" ]] && helm_cmd+=(--set-string "service.nodePorts.amqp=${AMQP_NODE_PORT}" --set-string "service.nodePorts.manager=${MANAGER_NODE_PORT}")
  [[ -z "${SERVICE_MONITOR_NAMESPACE}" || "${ENABLE_SERVICEMONITOR}" != "true" ]] || helm_cmd+=(--set-string "metrics.serviceMonitor.namespace=${SERVICE_MONITOR_NAMESPACE}")
  [[ -z "${SERVICE_MONITOR_SCRAPE_TIMEOUT}" || "${ENABLE_SERVICEMONITOR}" != "true" ]] || helm_cmd+=(--set-string "metrics.serviceMonitor.default.scrapeTimeout=${SERVICE_MONITOR_SCRAPE_TIMEOUT}")
  helm_cmd+=("${RESOURCE_HELM_ARGS[@]}")
  [[ ${#HELM_ARGS[@]} -eq 0 ]] || helm_cmd+=("${HELM_ARGS[@]}")

  section "Helm Command Preview"; preview_command "${helm_cmd[@]}"
  "${helm_cmd[@]}"
  success "RabbitMQ cluster install or upgrade completed"
}

show_post_install_info() {
  section "Deployment Result"
  kubectl get pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  echo
  echo "Auth Secret: ${NAMESPACE}/${RABBITMQ_SECRET_NAME} (values are not printed)"
  [[ "${COOKIE_ROTATION_DOWNTIME}" == "true" ]] && warn "Erlang cookie rotation completed with a full-cluster restart; verify all nodes and quorum queues before restoring traffic."
}

uninstall_release() {
  if release_exists; then helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"; success "Release ${RELEASE_NAME} uninstalled"; else warn "Helm release not found"; fi
  if [[ "${DELETE_PVC}" == "true" ]]; then kubectl delete pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" --ignore-not-found=true; success "PVC cleanup requested"; fi
  log "Authentication Secret is retained intentionally: ${NAMESPACE}/${RABBITMQ_SECRET_NAME:-${RELEASE_NAME}-auth}"
}

show_status() {
  section "Helm Status"; helm status "${RELEASE_NAME}" -n "${NAMESPACE}" || warn "Release not found"
  section "Kubernetes Resources"; kubectl get statefulset,pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
}

main() {
  parse_args "$@"; normalize_flags; banner
  case "${ACTION}" in
    help) usage ;;
    preflight) check_deps; extract_payload; run_upgrade_preflight "${TARGET_SERIES}" ;;
    install)
      check_deps; validate_storage_policy; confirm; extract_payload; load_image_metadata; ensure_namespace; check_existing_series_upgrade; check_servicemonitor_support; check_prometheusrule_support; prepare_images; ensure_auth_secret; install_release; show_post_install_info ;;
    uninstall) check_deps; confirm; uninstall_release ;;
    status) check_deps; show_status ;;
    *) die "Unsupported action: ${ACTION}" ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
