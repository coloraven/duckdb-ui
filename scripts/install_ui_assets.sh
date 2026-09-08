#!/usr/bin/env bash
# Install mirrored UI assets + optional fork extension helpers (Linux/macOS).
# Persists the extension as ui_offline.duckdb_extension under
# ~/.duckdb/extensions/{version}/{platform}/ — never official ui.duckdb_extension.
set -euo pipefail

ASSETS_TGZ=${1:?"usage: $0 <ui-assets.tar.gz> [target_assets_dir] [extension_zip]"}
TARGET=${2:-"${HOME}/.duckdb/extension_data/ui/assets"}
EXT_ZIP=${3:-}

DUCKDB_BIN=${DUCKDB:-duckdb}
DUCKDB_VERSION=${DUCKDB_VERSION:-}
if [[ -z "${DUCKDB_VERSION}" ]]; then
  if command -v "${DUCKDB_BIN}" >/dev/null 2>&1; then
    DUCKDB_VERSION=$("${DUCKDB_BIN}" -csv -noheader -c "SELECT version();" 2>/dev/null | tr -d '[:space:]' || true)
  fi
fi
DUCKDB_VERSION=${DUCKDB_VERSION:-v1.5.5}
case "${DUCKDB_VERSION}" in
  v*) ;;
  *) DUCKDB_VERSION="v${DUCKDB_VERSION}" ;;
esac

uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)
case "${uname_s}-${uname_m}" in
  Linux-x86_64|Linux-amd64) PLATFORM=linux_amd64 ;;
  Linux-aarch64|Linux-arm64) PLATFORM=linux_arm64 ;;
  Darwin-x86_64) PLATFORM=osx_amd64 ;;
  Darwin-arm64) PLATFORM=osx_arm64 ;;
  *) PLATFORM=linux_amd64 ;;
esac

EXT_DIR="${HOME}/.duckdb/extensions/${DUCKDB_VERSION}/${PLATFORM}"
FORK_EXT="${EXT_DIR}/ui_offline.duckdb_extension"

mkdir -p "${TARGET}"
# Archives ship with a top-level ui-assets/ directory (for "Extract here" UX).
if tar -tzf "${ASSETS_TGZ}" | head -n 1 | grep -q '^ui-assets/'; then
  tar -xzf "${ASSETS_TGZ}" -C "${TARGET}" --strip-components=1
else
  tar -xzf "${ASSETS_TGZ}" -C "${TARGET}"
fi
echo "Installed UI assets into ${TARGET}"

if [[ -n "${EXT_ZIP}" ]]; then
  mkdir -p "${EXT_DIR}"
  stage=$(mktemp -d)
  cleanup() { rm -rf "${stage}"; }
  trap cleanup EXIT
  unzip -o -q "${EXT_ZIP}" -d "${stage}"
  if [[ -f "${stage}/ui_offline.duckdb_extension" ]]; then
    cp -f "${stage}/ui_offline.duckdb_extension" "${FORK_EXT}"
  elif [[ -f "${stage}/ui-offline.duckdb_extension" ]]; then
    cp -f "${stage}/ui-offline.duckdb_extension" "${FORK_EXT}"
  else
    found=$(find "${stage}" -name '*.duckdb_extension' ! -name 'ui.duckdb_extension' | head -n 1 || true)
    if [[ -z "${found}" ]]; then
      found=$(find "${stage}" -name '*.duckdb_extension' | head -n 1 || true)
    fi
    [[ -n "${found}" ]] || { echo "No .duckdb_extension in ${EXT_ZIP}" >&2; exit 1; }
    cp -f "${found}" "${FORK_EXT}"
  fi
  echo "Installed fork extension as ${FORK_EXT}"
  echo "Official ui.duckdb_extension in ${EXT_DIR} (if present) was left untouched."
fi

echo
echo "Load the fork extension directly (entrypoint is ui_offline):"
echo "  duckdb -unsigned"
echo "  LOAD '${FORK_EXT}';"
echo "  -- or: LOAD ui_offline;"
echo "  SET ui_assets_path='${TARGET}';"
echo "  -- optional air-gap: SET ui_offline=true;"
echo "  CALL start_ui_server();"
echo
echo "Do NOT replace ~/.duckdb/extensions/.../ui.duckdb_extension with this fork."
