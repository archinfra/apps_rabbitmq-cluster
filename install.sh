#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="rabbitmq-cluster"
APP_VERSION="0.1.3"
PACKAGE_PROFILE="integrated"
WORKDIR="/tmp/${APP_NAME}-installer"
CHART_DIR="${WORKDIR}/charts/rabbitmq"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"

ACTION="help"
RELEASE_NAME="rabbitmq-cluster"
NAMESPACE="aict"
RABBITMQ_REPLICAS="3"
RABBITMQ_USERNAME="admin"
RABBITMQ_PASSWORD="RabbitMQ@Passw0rd"
RABBITMQ_ERLANG_COOKIE="ArchInfraRabbitMQCookie2026"
STORAGE_CLASS="nfs"
STORAGE_SIZE="8Gi"
SERVICE_TYPE="ClusterIP"
AMQP_NODE_PORT="30672"
MANAGER_NODE_PORT="31672"
IMAGE_PULL_POLICY="IfNotPresent"
WAIT_TIMEOUT="10m"
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
REGISTRY_USER="admin"
REGISTRY_PASS="passw0rd"
SKIP_IMAGE_PREPARE="false"
DELETE_PVC="false"
ENABLE_METRICS="true"
ENABLE_SERVICEMONITOR="true"
SERVICE_MONITOR_NAMESPACE=""
SERVICE_MONITOR_INTERVAL="30s"
SERVICE_MONITOR_SCRAPE_TIMEOUT=""
AUTO_YES="false"

HELM_ARGS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

declare -A IMAGE_DEFAULT_TARGETS=()
declare -A IMAGE_EFFECTIVE_TARGETS=()
declare -A IMAGE_LOAD_REFS=()

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}$*${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
}

program_name() {
  basename "$0"
}

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
  ${cmd} <install|uninstall|status|help> [options] [-- <helm_args>]
  ${cmd} -h|--help

Actions:
  install       Prepare images and install or upgrade the RabbitMQ cluster release
  uninstall     Uninstall the RabbitMQ cluster release
  status        Show Helm release and Kubernetes resource status
  help          Show this message

Core options:
  -n, --namespace <ns>                 Namespace, default: ${NAMESPACE}
  --release-name <name>                Helm release name, default: ${RELEASE_NAME}
  --replicas <num>                     RabbitMQ replicas, default: ${RABBITMQ_REPLICAS}
  --username <name>                    RabbitMQ username, default: ${RABBITMQ_USERNAME}
  --password <pwd>                     RabbitMQ password, default: ${RABBITMQ_PASSWORD}
  --erlang-cookie <value>              Erlang cookie, default: ${RABBITMQ_ERLANG_COOKIE}
  --storage-class <name>               StorageClass, default: ${STORAGE_CLASS}
  --storage-size <size>                PVC size, default: ${STORAGE_SIZE}
  --service-type <type>                ClusterIP|NodePort|LoadBalancer, default: ${SERVICE_TYPE}
  --amqp-node-port <port>              AMQP NodePort when service is NodePort/LB, default: ${AMQP_NODE_PORT}
  --manager-node-port <port>           Management NodePort when service is NodePort/LB, default: ${MANAGER_NODE_PORT}

Monitoring:
  --enable-metrics                     Enable RabbitMQ Prometheus metrics, default: true
  --disable-metrics                    Disable RabbitMQ Prometheus metrics
  --enable-servicemonitor              Create ServiceMonitor and auto-enable metrics, default: true
  --disable-servicemonitor             Disable ServiceMonitor
  --service-monitor-namespace <ns>     Optional namespace for the ServiceMonitor
  --service-monitor-interval <value>   ServiceMonitor interval, default: ${SERVICE_MONITOR_INTERVAL}
  --service-monitor-scrape-timeout <v> ServiceMonitor scrape timeout

Image and rollout:
  --registry <repo-prefix>             Target image repo prefix, default: ${REGISTRY_REPO}
  --registry-user <user>               Registry username, default: ${REGISTRY_USER}
  --registry-password <password>       Registry password, default: <hidden>
  --image-pull-policy <policy>         Always|IfNotPresent|Never, default: ${IMAGE_PULL_POLICY}
  --skip-image-prepare                 Reuse images already present in the target registry
  --wait-timeout <duration>            Helm wait timeout, default: ${WAIT_TIMEOUT}

Other:
  --delete-pvc                         With uninstall, also delete PVCs created by the release
  -y, --yes                            Skip confirmation
  -h, --help                           Show help

Examples:
  ${cmd} install -y
  ${cmd} install --service-type NodePort --manager-node-port 31672 --amqp-node-port 30672 -y
  ${cmd} install --disable-servicemonitor --disable-metrics -y
  ${cmd} install --registry harbor.example.com/kube4 --skip-image-prepare -y
  ${cmd} status -n ${NAMESPACE}
  ${cmd} uninstall --delete-pvc -y
EOF
}

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

parse_args() {
  if [[ $# -eq 0 ]]; then
    ACTION="help"
    return
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help)
        ACTION="$1"
        shift
        ;;
      -n|--namespace)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        NAMESPACE="$2"
        shift 2
        ;;
      --release-name)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        RELEASE_NAME="$2"
        shift 2
        ;;
      --replicas)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        RABBITMQ_REPLICAS="$2"
        shift 2
        ;;
      --username)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        RABBITMQ_USERNAME="$2"
        shift 2
        ;;
      --password)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        RABBITMQ_PASSWORD="$2"
        shift 2
        ;;
      --erlang-cookie)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        RABBITMQ_ERLANG_COOKIE="$2"
        shift 2
        ;;
      --storage-class)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        STORAGE_CLASS="$2"
        shift 2
        ;;
      --storage-size)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        STORAGE_SIZE="$2"
        shift 2
        ;;
      --service-type)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_TYPE="$2"
        shift 2
        ;;
      --amqp-node-port)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        AMQP_NODE_PORT="$2"
        shift 2
        ;;
      --manager-node-port)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MANAGER_NODE_PORT="$2"
        shift 2
        ;;
      --enable-metrics)
        ENABLE_METRICS="true"
        shift
        ;;
      --disable-metrics)
        ENABLE_METRICS="false"
        ENABLE_SERVICEMONITOR="false"
        shift
        ;;
      --enable-servicemonitor)
        ENABLE_SERVICEMONITOR="true"
        ENABLE_METRICS="true"
        shift
        ;;
      --disable-servicemonitor)
        ENABLE_SERVICEMONITOR="false"
        shift
        ;;
      --service-monitor-namespace)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_MONITOR_NAMESPACE="$2"
        shift 2
        ;;
      --service-monitor-interval)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_MONITOR_INTERVAL="$2"
        shift 2
        ;;
      --service-monitor-scrape-timeout)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_MONITOR_SCRAPE_TIMEOUT="$2"
        shift 2
        ;;
      --registry)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_REPO="$2"
        REGISTRY_REPO_EXPLICIT="true"
        shift 2
        ;;
      --registry-user)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_USER="$2"
        shift 2
        ;;
      --registry-password)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_PASS="$2"
        shift 2
        ;;
      --image-pull-policy)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        IMAGE_PULL_POLICY="$2"
        shift 2
        ;;
      --skip-image-prepare)
        SKIP_IMAGE_PREPARE="true"
        shift
        ;;
      --wait-timeout)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        WAIT_TIMEOUT="$2"
        shift 2
        ;;
      --delete-pvc)
        DELETE_PVC="true"
        shift
        ;;
      -y|--yes)
        AUTO_YES="true"
        shift
        ;;
      -h|--help)
        ACTION="help"
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          HELM_ARGS+=("$1")
          shift
        done
        break
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

is_valid_nodeport() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  (( "$1" >= 30000 && "$1" <= 32767 ))
}

normalize_flags() {
  case "${SERVICE_TYPE}" in
    ClusterIP|NodePort|LoadBalancer) ;;
    *)
      die "Unsupported service type: ${SERVICE_TYPE}"
      ;;
  esac

  case "${IMAGE_PULL_POLICY}" in
    Always|IfNotPresent|Never) ;;
    *)
      die "Unsupported image pull policy: ${IMAGE_PULL_POLICY}"
      ;;
  esac

  [[ "${RABBITMQ_REPLICAS}" =~ ^[0-9]+$ ]] || die "Replicas must be a positive integer"
  (( RABBITMQ_REPLICAS >= 1 )) || die "Replicas must be at least 1"

  if [[ "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    ENABLE_METRICS="true"
  fi

  if [[ "${SERVICE_TYPE}" == "NodePort" || "${SERVICE_TYPE}" == "LoadBalancer" ]]; then
    is_valid_nodeport "${AMQP_NODE_PORT}" || die "AMQP NodePort must be in range 30000-32767, got: ${AMQP_NODE_PORT}"
    is_valid_nodeport "${MANAGER_NODE_PORT}" || die "Manager NodePort must be in range 30000-32767, got: ${MANAGER_NODE_PORT}"
  fi
}

check_deps() {
  command -v helm >/dev/null 2>&1 || die "helm is required"
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  if [[ "${ACTION}" == "install" && "${SKIP_IMAGE_PREPARE}" != "true" ]]; then
    command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
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
    echo "StorageClass            : ${STORAGE_CLASS}"
    echo "Storage size            : ${STORAGE_SIZE}"
    echo "Service type            : ${SERVICE_TYPE}"
    echo "Metrics                 : ${ENABLE_METRICS}"
    echo "ServiceMonitor          : ${ENABLE_SERVICEMONITOR}"
    echo "Registry repo           : ${REGISTRY_REPO}"
    echo "Skip image prepare      : ${SKIP_IMAGE_PREPARE}"
    echo "Wait timeout            : ${WAIT_TIMEOUT}"
  fi
  if [[ "${ACTION}" == "uninstall" ]]; then
    echo "Delete PVC              : ${DELETE_PVC}"
  fi
  if [[ ${#HELM_ARGS[@]} -gt 0 ]]; then
    echo "Helm extra args         : ${HELM_ARGS[*]}"
  fi
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
    case "${byte_hex}" in
      0a|0d)
        skip_bytes=$((skip_bytes + 1))
        ;;
      "")
        die "Installer payload boundary is invalid"
        ;;
      *)
        break
        ;;
    esac
  done

  printf '%s' "$((payload_offset + skip_bytes))"
}

extract_payload() {
  local payload_offset
  payload_offset="$(payload_start_offset)"

  section "Extract Payload"
  rm -rf "${WORKDIR}"
  mkdir -p "${WORKDIR}"
  tail -c +"${payload_offset}" "$0" | tar -xz -C "${WORKDIR}" || die "failed to extract payload"

  [[ -d "${CHART_DIR}" ]] || die "Missing chart payload"
  [[ -f "${IMAGE_INDEX}" ]] || die "Missing image metadata payload"
}

image_name_from_ref() {
  local ref="$1"
  local name_tag="${ref##*/}"
  echo "${name_tag%%:*}"
}

image_name_tag_from_ref() {
  local ref="$1"
  echo "${ref##*/}"
}

resolve_target_ref() {
  local default_ref="$1"
  if [[ "${REGISTRY_REPO_EXPLICIT}" == "true" ]]; then
    echo "${REGISTRY_REPO}/$(image_name_tag_from_ref "${default_ref}")"
  else
    echo "${default_ref}"
  fi
}

image_registry_from_ref() {
  local ref="$1"
  echo "${ref%%/*}"
}

image_repository_from_ref() {
  local ref="$1"
  local remainder="${ref#*/}"
  echo "${remainder%:*}"
}

image_tag_from_ref() {
  local ref="$1"
  echo "${ref##*:}"
}

load_image_metadata() {
  while IFS=$'\t' read -r tar_name load_ref default_target_ref _platform; do
    [[ -n "${tar_name}" ]] || continue
    IMAGE_LOAD_REFS["${tar_name}"]="${load_ref}"
    IMAGE_DEFAULT_TARGETS["${tar_name}"]="${default_target_ref}"
    IMAGE_EFFECTIVE_TARGETS["${tar_name}"]="$(resolve_target_ref "${default_target_ref}")"
  done < "${IMAGE_INDEX}"
}

find_image_ref_by_name() {
  local wanted_name="$1"
  local tar_name
  for tar_name in "${!IMAGE_EFFECTIVE_TARGETS[@]}"; do
    if [[ "$(image_name_from_ref "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}")" == "${wanted_name}" ]]; then
      echo "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"
      return 0
    fi
  done
  return 1
}

docker_image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

docker_login() {
  local registry_host="${REGISTRY_REPO%%/*}"
  log "Logging into registry ${registry_host}"
  if ! echo "${REGISTRY_PASS}" | docker login "${registry_host}" -u "${REGISTRY_USER}" --password-stdin >/dev/null 2>&1; then
    warn "docker login failed for ${registry_host}; continuing and letting push decide"
  fi
}

prepare_images() {
  [[ "${SKIP_IMAGE_PREPARE}" == "true" ]] && {
    log "Skipping image prepare because --skip-image-prepare was requested"
    return 0
  }

  docker_login

  local tar_name load_ref default_target_ref target_ref tar_path
  while IFS=$'\t' read -r tar_name load_ref default_target_ref _platform; do
    [[ -n "${tar_name}" ]] || continue
    tar_path="${IMAGE_DIR}/${tar_name}"
    [[ -f "${tar_path}" ]] || die "Missing image tar: ${tar_path}"

    target_ref="${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"

    if docker_image_exists "${target_ref}"; then
      log "Reusing local image ${target_ref}"
    else
      log "Loading ${tar_name}"
      docker load -i "${tar_path}" >/dev/null

      if [[ "${load_ref}" != "${target_ref}" ]]; then
        log "Tagging ${load_ref} -> ${target_ref}"
        docker tag "${load_ref}" "${target_ref}"
      fi
    fi

    log "Pushing ${target_ref}"
    docker push "${target_ref}" >/dev/null
  done < "${IMAGE_INDEX}"

  success "Image prepare completed"
}

ensure_namespace() {
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    log "Creating namespace ${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}" >/dev/null
  fi
}

check_servicemonitor_support() {
  if [[ "${ENABLE_SERVICEMONITOR}" != "true" ]]; then
    return 0
  fi

  if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    warn "ServiceMonitor CRD not found; disabling ServiceMonitor for this install"
    ENABLE_SERVICEMONITOR="false"
  fi
}

preview_command() {
  local rendered=()
  local arg
  for arg in "$@"; do
    rendered+=("$(printf '%q' "${arg}")")
  done
  printf '%s ' "${rendered[@]}"
  echo
}

install_release() {
  local rabbitmq_image os_shell_image
  rabbitmq_image="$(find_image_ref_by_name "rabbitmq")" || die "Unable to resolve rabbitmq image"
  os_shell_image="$(find_image_ref_by_name "os-shell")" || die "Unable to resolve os-shell image"

  local helm_cmd=(
    helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}"
    -n "${NAMESPACE}"
    --create-namespace
    --wait
    --timeout "${WAIT_TIMEOUT}"
    --set "replicaCount=${RABBITMQ_REPLICAS}"
    --set "clustering.enabled=true"
    --set "global.security.allowInsecureImages=true"
    --set-string "auth.username=${RABBITMQ_USERNAME}"
    --set-string "auth.password=${RABBITMQ_PASSWORD}"
    --set-string "auth.erlangCookie=${RABBITMQ_ERLANG_COOKIE}"
    --set "auth.securePassword=false"
    --set "persistence.enabled=true"
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
    --set-string "metrics.serviceMonitor.default.interval=${SERVICE_MONITOR_INTERVAL}"
    --set-string "metrics.serviceMonitor.labels.monitoring\\.archinfra\\.io/stack=default"
  )

  if [[ "${SERVICE_TYPE}" == "NodePort" || "${SERVICE_TYPE}" == "LoadBalancer" ]]; then
    helm_cmd+=(
      --set-string "service.nodePorts.amqp=${AMQP_NODE_PORT}"
      --set-string "service.nodePorts.manager=${MANAGER_NODE_PORT}"
    )
  fi

  if [[ -n "${SERVICE_MONITOR_NAMESPACE}" && "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    helm_cmd+=(--set-string "metrics.serviceMonitor.namespace=${SERVICE_MONITOR_NAMESPACE}")
  fi

  if [[ -n "${SERVICE_MONITOR_SCRAPE_TIMEOUT}" && "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    helm_cmd+=(--set-string "metrics.serviceMonitor.default.scrapeTimeout=${SERVICE_MONITOR_SCRAPE_TIMEOUT}")
  fi

  if [[ ${#HELM_ARGS[@]} -gt 0 ]]; then
    helm_cmd+=("${HELM_ARGS[@]}")
  fi

  section "Helm Command Preview"
  preview_command "${helm_cmd[@]}"

  ensure_namespace
  "${helm_cmd[@]}"
  success "RabbitMQ cluster install or upgrade completed"
}

show_post_install_info() {
  section "Deployment Result"
  kubectl get pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor -n "${SERVICE_MONITOR_NAMESPACE:-${NAMESPACE}}" "${RELEASE_NAME}" >/dev/null 2>&1 && \
      kubectl get servicemonitor -n "${SERVICE_MONITOR_NAMESPACE:-${NAMESPACE}}" "${RELEASE_NAME}" || true
  fi
}

uninstall_release() {
  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
    success "Release ${RELEASE_NAME} uninstalled"
  else
    warn "Helm release ${RELEASE_NAME} not found in namespace ${NAMESPACE}"
  fi

  if [[ "${DELETE_PVC}" == "true" ]]; then
    kubectl delete pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" --ignore-not-found=true
    success "PVC cleanup requested"
  fi
}

show_status() {
  section "Helm Status"
  helm status "${RELEASE_NAME}" -n "${NAMESPACE}" || warn "Release ${RELEASE_NAME} not found"

  section "Kubernetes Resources"
  kubectl get statefulset,pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor -A | grep "${RELEASE_NAME}" || true
  fi
}

main() {
  parse_args "$@"
  normalize_flags
  banner

  case "${ACTION}" in
    help)
      usage
      ;;
    install)
      check_deps
      confirm
      extract_payload
      load_image_metadata
      check_servicemonitor_support
      prepare_images
      install_release
      show_post_install_info
      ;;
    uninstall)
      check_deps
      confirm
      uninstall_release
      ;;
    status)
      check_deps
      show_status
      ;;
    *)
      die "Unsupported action: ${ACTION}"
      ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
