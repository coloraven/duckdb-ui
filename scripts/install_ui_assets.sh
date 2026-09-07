#!/usr/bin/env bash
# Install mirrored UI assets + optional fork extension helpers (Linux/macOS).
# Persists the extension as ui-offline.duckdb_extension (never official ui.duckdb_extension).
set -euo pipefail

ASSETS_TGZ=${1:?"usage: $0 <ui-assets.tar.gz> [target_assets_dir] [extension_zip]"}
TARGET=${2:-"${HOME}/.duckdb/extension_data/ui/assets"}
EXT_ZIP=${3:-}
UI_HOME="${HOME}/.duckdb/extension_data/ui"
FORK_EXT="${UI_HOME}/ui-offline.duckdb_extension"

mkdir -p "${TARGET}"
# Archives ship with a top-level ui-assets/ directory (for "Extract here" UX).
if tar -tzf "${ASSETS_TGZ}" | head -n 1 | grep -q '^ui-assets/'; then
  tar -xzf "${ASSETS_TGZ}" -C "${TARGET}" --strip-components=1
else
  tar -xzf "${ASSETS_TGZ}" -C "${TARGET}"
fi
echo "Installed UI assets into ${TARGET}"

if [[ -n "${EXT_ZIP}" ]]; then
  mkdir -p "${UI_HOME}"
  stage=$(mktemp -d)
  cleanup() { rm -rf "${stage}"; }
  trap cleanup EXIT
  unzip -o -q "${EXT_ZIP}" -d "${stage}"
  if [[ -f "${stage}/ui-offline.duckdb_extension" ]]; then
    cp -f "${stage}/ui-offline.duckdb_extension" "${FORK_EXT}"
  elif [[ -f "${stage}/ui.duckdb_extension" ]]; then
    cp -f "${stage}/ui.duckdb_extension" "${FORK_EXT}"
  else
    found=$(find "${stage}" -name '*.duckdb_extension' | head -n 1 || true)
    [[ -n "${found}" ]] || { echo "No .duckdb_extension in ${EXT_ZIP}" >&2; exit 1; }
    cp -f "${found}" "${FORK_EXT}"
  fi
  rm -f "${UI_HOME}/ui.duckdb_extension"
  echo "Installed fork extension as ${FORK_EXT}"
fi

echo
echo "DuckDB requires stem 'ui' at LOAD time. Copy to a private temp dir first:"
echo "  mkdir -p /tmp/duckdb-ui-fork-load"
echo "  cp '${FORK_EXT}' /tmp/duckdb-ui-fork-load/ui.duckdb_extension"
echo "  cd /tmp/duckdb-ui-fork-load && duckdb -unsigned"
echo "  LOAD './ui.duckdb_extension';"
echo "  SET ui_assets_path='${TARGET}';"
echo "  -- optional air-gap: SET ui_offline=true;"
echo "  CALL start_ui_server();"
echo
echo "Do NOT install this fork into ~/.duckdb/extensions/.../ui.duckdb_extension."
