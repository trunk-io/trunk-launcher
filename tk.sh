#!/bin/bash
#shellcheck disable=SC2310,SC2311

set -e

REPO="trunk-io/trunk-cli-releases"

error() {
  echo "Error: $1" >&2
  exit 1
}

get_trunk_version() {
  git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
  tk_version_path="${git_toplevel}/.tk/version"
  if [[ ! -f ${tk_version_path} ]]; then
    return 1
  fi
  tr <"${tk_version_path}" -d '[:space:]'
}

get_latest_release() {
  local latest_release_url="https://api.github.com/repos/${REPO}/releases/latest"
  local json

  if command -v curl >/dev/null 2>&1; then
    json=$(curl -fs "${latest_release_url}")
  elif command -v wget >/dev/null 2>&1; then
    json=$(wget -qO- "${latest_release_url}")
  else
    error "Neither curl nor wget is available"
  fi
  echo "${json}" | grep -Po '"tag_name": *"\K[^"]+'
}

get_trunk_version_or_latest_release() {
  local trunk_version

  if trunk_version=$(get_trunk_version); then
    echo "${trunk_version}"
    return
  fi
  local latest_release
  if latest_release=$(get_latest_release); then
    echo "${latest_release}"
    return
  fi
  error "Failed to get tk version or latest release"
}

detect_platform() {
  local os arch kernel machine
  kernel=$(uname -s)
  machine=$(uname -m)

  case "${kernel}" in
  Darwin) os="apple-darwin" ;;
  Linux) os="unknown-linux-musl" ;;
  *) error "Unsupported operating system: ${kernel}" ;;
  esac

  case "${machine}" in
  x86_64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  *) error "Unsupported architecture: ${machine}" ;;
  esac

  echo "${arch}-${os}"
}

download() {
  local url="$1"
  local output_path="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL -o "${output_path}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${output_path}" "${url}"
  else
    error "Neither curl nor wget is available"
  fi
}

TRUNK_VERSION=$(get_trunk_version_or_latest_release)
PLATFORM=$(detect_platform)
CACHE_DIR="${HOME}/.cache/trunk-cli/cli"
TARGET_DIR="${CACHE_DIR}/${TRUNK_VERSION}-${PLATFORM}"
BINARY_PATH="${TARGET_DIR}/trunk_cli"

# Download and extract the binary if not already cached
if [[ ! -f ${BINARY_PATH} ]]; then
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "${TEMP_DIR}"' EXIT
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TRUNK_VERSION}/trunk_cli-${PLATFORM}.tar.gz"
  ARCHIVE_PATH="${TEMP_DIR}/trunk_cli-${TRUNK_VERSION}.tar.gz"
  download "${DOWNLOAD_URL}" "${ARCHIVE_PATH}"
  mkdir -p "${TARGET_DIR}"
  tar -xzf "${ARCHIVE_PATH}" -C "${TARGET_DIR}"
fi

# Execute the binary with any forwarded arguments
exec -a "$0" "${BINARY_PATH}" "$@"
