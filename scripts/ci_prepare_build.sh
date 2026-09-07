#!/usr/bin/env bash
# CI helper: materialize upstream duckdb-ui + apply this fork's overlay.
# Expects:
#   FORK_ROOT  — path to this (thin) repo checkout (default: ./fork)
#   WORK_ROOT  — path to build tree (default: .)
set -euo pipefail

FORK_ROOT="$(cd "${FORK_ROOT:-fork}" && pwd)"
WORK_ROOT_IN="${WORK_ROOT:-.}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/duckdb/duckdb-ui.git}"
UPSTREAM_REF="${UPSTREAM_REF:-main}"

if [[ ! -d "$FORK_ROOT/overlay" ]]; then
  echo "error: missing $FORK_ROOT/overlay" >&2
  exit 1
fi

if [[ ! -f "$WORK_ROOT_IN/CMakeLists.txt" ]]; then
  echo "Cloning $UPSTREAM_REPO ($UPSTREAM_REF) into $WORK_ROOT_IN ..."
  rm -rf "$WORK_ROOT_IN"
  git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$WORK_ROOT_IN"
fi
WORK_ROOT="$(cd "$WORK_ROOT_IN" && pwd)"

bash "$FORK_ROOT/scripts/apply_overlay.sh" "$WORK_ROOT"

# Expose fork scripts used by packaging / asset mirror (theme, fork overlays, start_ui).
mkdir -p "$WORK_ROOT/scripts"
# Keep upstream scripts; add/overwrite fork helpers that live only in this repo.
for name in mirror_ui_assets.py start_ui.ps1 install_ui_assets.sh \
            dev_theme.ps1 apply_overlay.sh apply_overlay.ps1 check_no_openssl_dlls.py; do
  if [[ -f "$FORK_ROOT/scripts/$name" ]]; then
    cp -f "$FORK_ROOT/scripts/$name" "$WORK_ROOT/scripts/$name"
  fi
done
if [[ -d "$FORK_ROOT/scripts/theme" ]]; then
  rm -rf "$WORK_ROOT/scripts/theme"
  cp -a "$FORK_ROOT/scripts/theme" "$WORK_ROOT/scripts/theme"
fi
if [[ -d "$FORK_ROOT/scripts/fork" ]]; then
  rm -rf "$WORK_ROOT/scripts/fork"
  cp -a "$FORK_ROOT/scripts/fork" "$WORK_ROOT/scripts/fork"
fi

echo "Prepared upstream+overlay at $WORK_ROOT"
if [[ -f "$FORK_ROOT/upstream.sha" ]]; then
  echo "fork upstream.sha=$(cat "$FORK_ROOT/upstream.sha")"
fi
git -C "$WORK_ROOT" rev-parse HEAD > "$WORK_ROOT/.upstream-head-sha" || true
cat "$WORK_ROOT/.upstream-head-sha"
