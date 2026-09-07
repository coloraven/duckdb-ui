#!/usr/bin/env bash
# Apply this fork's overlay onto an upstream duckdb/duckdb-ui checkout.
# Usage: ./scripts/apply_overlay.sh /path/to/duckdb-ui
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_IN="${1:-}"
if [[ -z "$TARGET_IN" ]]; then
  echo "usage: $0 /path/to/upstream-duckdb-ui" >&2
  exit 1
fi
# Resolve absolute path BEFORE any cd — relative targets break once we enter OVERLAY/.
TARGET="$(cd "$TARGET_IN" && pwd)"
if [[ ! -f "$TARGET/CMakeLists.txt" || ! -d "$TARGET/src" ]]; then
  echo "error: $TARGET does not look like duckdb/duckdb-ui" >&2
  exit 1
fi
OVERLAY="$ROOT/overlay"
if [[ ! -d "$OVERLAY" ]]; then
  echo "error: overlay missing at $OVERLAY" >&2
  exit 1
fi

applied=0
# Do not cd into OVERLAY: keep TARGET absolute and stable.
while IFS= read -r -d '' f; do
  rel="${f#"$OVERLAY"/}"
  case "$rel" in
    OVERLAY.md|README.md) continue ;;
  esac
  mkdir -p "$TARGET/$(dirname "$rel")"
  cp -f "$f" "$TARGET/$rel"
  echo "applied $rel"
  applied=$((applied + 1))
done < <(find "$OVERLAY" -type f -print0)

if [[ "$applied" -lt 1 ]]; then
  echo "error: no overlay files applied from $OVERLAY" >&2
  exit 1
fi

# Fail closed: fork settings must be present or CI would ship vanilla upstream.
for needle in ui_assets_path ui_offline ui_local_host theme_inject.cpp; do
  if ! grep -R -q -- "$needle" "$TARGET/src" "$TARGET/CMakeLists.txt"; then
    echo "error: overlay verify failed — '$needle' not found under $TARGET after apply" >&2
    exit 1
  fi
done

echo "Overlay applied ($applied files) onto $TARGET"
