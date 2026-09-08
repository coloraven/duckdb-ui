# Overlay

Files here (except `OVERLAY.md`) are copied onto a clean `duckdb/duckdb-ui`
checkout at CI / local build time via `scripts/apply_overlay.sh`.

## Extension name

The loadable extension is built as **`ui_offline`** (not upstream `ui`):

- Artifact: `ui_offline.duckdb_extension`
- Header / class: `ui_offline_extension.hpp` / `UiOfflineExtension` (DuckDB static-link codegen requires `{name}_extension.hpp` and CamelCase `*Extension`)
- Entrypoint symbol: `ui_offline_duckdb_cpp_init`
- `LOAD ui_offline` / `LOAD './…/ui_offline.duckdb_extension'` — no temp rename to `ui.*`

Hyphenated names like `ui-offline` are not valid C entrypoint identifiers.
