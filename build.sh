#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${ROOT_DIR}/.build-payload"
PAYLOAD_DIR="${TEMP_DIR}/payload"
PAYLOAD_FILE="${TEMP_DIR}/payload.tar.gz"
DIST_DIR="${ROOT_DIR}/dist"
IMAGES_DIR="${ROOT_DIR}/images"
IMAGE_JSON="${IMAGES_DIR}/image.json"
CHART_DIR="${ROOT_DIR}/charts/rabbitmq"
INSTALLER_TEMPLATE="${ROOT_DIR}/install.sh"
INSTALLER_BASENAME="rabbitmq-cluster-installer"

ARCH="amd64"
PLATFORM="linux/amd64"
BUILD_ALL_ARCH="false"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
cleanup() { rm -rf "${TEMP_DIR}"; }
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--arch amd64|arm64|all]
EOF
}

normalize_arch() {
  case "$1" in
    amd64|amd|x86_64) ARCH="amd64"; PLATFORM="linux/amd64"; BUILD_ALL_ARCH="false" ;;
    arm64|arm|aarch64) ARCH="arm64"; PLATFORM="linux/arm64"; BUILD_ALL_ARCH="false" ;;
    all) BUILD_ALL_ARCH="true" ;;
    *) die "Unsupported arch: $1" ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch|-a) [[ $# -ge 2 ]] || die "Missing value for $1"; normalize_arch "$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

check_requirements() {
  command -v jq >/dev/null 2>&1 || die "jq is required on the build host"
  command -v docker >/dev/null 2>&1 || die "docker is required"
  command -v helm >/dev/null 2>&1 || die "helm is required"
  [[ -f "${INSTALLER_TEMPLATE}" ]] || die "install.sh is missing"
  [[ -f "${IMAGE_JSON}" ]] || die "images/image.json is missing"
  [[ -d "${CHART_DIR}" ]] || die "charts/rabbitmq is missing"
  grep -q '^__PAYLOAD_BELOW__$' "${INSTALLER_TEMPLATE}" || die "install.sh is missing __PAYLOAD_BELOW__ marker"
}

prepare_chart_dependencies() {
  log "Building Helm chart dependencies for rabbitmq"
  helm dependency build "${CHART_DIR}" >/dev/null
}

prepare_directories() {
  rm -rf "${TEMP_DIR}"
  mkdir -p "${PAYLOAD_DIR}/charts" "${PAYLOAD_DIR}/images" "${DIST_DIR}"
}

image_name_tag_from_ref() { local ref="$1"; echo "${ref##*/}"; }
build_local_load_ref() { local target="$1"; echo "archinfra-payload/$(image_name_tag_from_ref "${target}")-${ARCH}"; }

prepare_images() {
  local arch="$1" platform="$2" count=0 item
  : > "${PAYLOAD_DIR}/images/image-index.tsv"
  jq --arg arch "${arch}" '[.[] | select(.arch == $arch)]' "${IMAGE_JSON}" > "${PAYLOAD_DIR}/images/image.json"

  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    local pull build_context default_target_ref tar_name load_ref item_platform
    pull="$(jq -r '.pull // empty' <<<"${item}")"
    build_context="$(jq -r '.build // empty' <<<"${item}")"
    default_target_ref="$(jq -r '.tag' <<<"${item}")"
    tar_name="$(jq -r '.tar' <<<"${item}")"
    item_platform="$(jq -r '.platform // empty' <<<"${item}")"
    [[ -n "${item_platform}" ]] || item_platform="${platform}"
    load_ref="$(build_local_load_ref "${default_target_ref}")"

    if [[ -n "${build_context}" ]]; then
      local context_path="${ROOT_DIR}/${build_context}"
      [[ -f "${context_path}/Dockerfile" ]] || die "Missing Dockerfile: ${context_path}/Dockerfile"
      log "Building ${load_ref} from ${build_context} for ${item_platform}"
      docker build --pull --platform "${item_platform}" -t "${load_ref}" "${context_path}"
    elif [[ -n "${pull}" ]]; then
      log "Pulling ${pull} for ${item_platform}"
      docker pull --platform "${item_platform}" "${pull}"
      docker tag "${pull}" "${load_ref}"
    else
      die "Image entry must contain exactly one of pull/build: ${item}"
    fi

    log "Saving ${load_ref} -> ${PAYLOAD_DIR}/images/${tar_name}"
    docker save -o "${PAYLOAD_DIR}/images/${tar_name}" "${load_ref}"
    printf '%s\t%s\t%s\t%s\n' "${tar_name}" "${load_ref}" "${default_target_ref}" "${item_platform}" >> "${PAYLOAD_DIR}/images/image-index.tsv"
    count=$((count + 1))
  done < <(jq -c --arg arch "${arch}" '.[] | select(.arch == $arch)' "${IMAGE_JSON}")

  (( count > 0 )) || die "No image definitions found for arch=${arch}"
  success "Prepared ${count} image(s) for arch=${arch}"
}

package_payload() {
  local arch="$1" installer_path="${DIST_DIR}/${INSTALLER_BASENAME}-${arch}.run"
  local checksum_path="${installer_path}.sha256"
  cp -R "${CHART_DIR}" "${PAYLOAD_DIR}/charts/"
  tar -C "${PAYLOAD_DIR}" -czf "${PAYLOAD_FILE}" .
  tar -tzf "${PAYLOAD_FILE}" >/dev/null
  cat "${INSTALLER_TEMPLATE}" "${PAYLOAD_FILE}" > "${installer_path}"
  chmod +x "${installer_path}"
  sha256sum "${installer_path}" | awk '{print $1}' > "${checksum_path}"
  printf '%s  %s\n' "$(cat "${checksum_path}")" "$(basename "${installer_path}")" | (cd "${DIST_DIR}" && sha256sum -c - >/dev/null)
  success "Generated $(basename "${installer_path}")"
}

build_one() {
  local arch="$1" platform="$2"
  ARCH="${arch}"; PLATFORM="${platform}"
  prepare_directories
  prepare_chart_dependencies
  prepare_images "${arch}" "${platform}"
  package_payload "${arch}"
}

main() {
  parse_args "$@"
  check_requirements
  if [[ "${BUILD_ALL_ARCH}" == "true" ]]; then
    build_one amd64 linux/amd64
    build_one arm64 linux/arm64
  else
    build_one "${ARCH}" "${PLATFORM}"
  fi
}

main "$@"
