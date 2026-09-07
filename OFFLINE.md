# Offline / air-gapped DuckDB UI (fork)

This repository is an **overlay-only** fork of `duckdb/duckdb-ui`: CI clones upstream, applies `overlay/`, then builds. It does **not** vendor the full upstream source tree.

## Two separate “local-first” layers

| Layer | What | Default |
| --- | --- | --- |
| **Release install** (`start_ui.ps1`) | GitHub `offline-latest` extension zip + `ui-assets.tar.gz` | No download if local files exist; only on miss or `-Fetch` |
| **Runtime assets** (extension) | Files under `ui_assets_path` | Local first; miss → `ui_remote_url` → write cache; next hit is local |

Browser XHR to MotherDuck / Datadog / Auth0 is **always CSP-blocked** (`connect-src 'self'`). Asset fill-in still works because the **extension server** fetches remotes server-side, not the browser.

### `ui_offline` (optional air-gap)

Kept only for strict environments that must never contact `ui_remote_url` even on a cache miss:

- `false` (default): local → miss → remote → cache
- `true` (`start_ui.ps1 -AirGap`): miss → HTTP 503 (no remote)

You do **not** need `ui_offline=true` for a fast local UI; CSP already stops the SPA from hanging on cloud APIs.

## What changed vs upstream

1. Settings: `ui_assets_path`, `ui_offline` (air-gap only), `ui_local_host` (Windows `127.0.0.1`)
2. Local-first asset serving + miss→cache
3. Always-on CSP for the local shell
4. `/version` mirrored or synthesized so the shell selects local HTTP mode
5. CI mirrors static assets + publishes with the extension
6. Fork injects: Dark+ theme, zh-CN dict, Path quote strip (+ ATTACH normalize on `/ddb/run`)
7. Artifacts named **`ui-offline.*`** (never overwrite official `ui.duckdb_extension`)

> Frontend source remains closed; this fork mirrors published CDN assets.

## Quick start

DuckDB **v1.5.5** + `-unsigned`. Rolling tag: [`offline-latest`](../../releases/tag/offline-latest).

**LOAD caveat:** copy `ui-offline.duckdb_extension` to a private temp dir as `ui.duckdb_extension` before `LOAD` (stem must be `ui`). `start_ui.ps1` does this.

```powershell
# Windows — local-first; downloads release only if missing or -Fetch
.\start_ui.ps1
.\start_ui.ps1 -Fetch          # refresh extension + assets from offline-latest
.\start_ui.ps1 -AirGap         # ui_offline=true (no remote asset fill)
.\start_ui.ps1 -NoStart        # install/ensure only
```

```sql
LOAD './ui.duckdb_extension';
SET ui_assets_path='~/.duckdb/extension_data/ui/assets';
-- optional: SET ui_offline=true;   -- air-gap only
CALL start_ui_server();
```

Open **`http://127.0.0.1:4213/`** (not `localhost` on Windows).

## Mirror assets yourself

```bash
python3 scripts/mirror_ui_assets.py --remote https://ui.duckdb.org --out ./dist/ui-assets
tar -C dist -czf ui-assets.tar.gz ui-assets
```

## Notes

- Hatchling Auth0 silent login is patched in the mirrored bundle (instant fail).
- CSP is the main fix for “opens after tens of seconds” on networks that cannot reach MotherDuck/Datadog.
- Details / naming rules: keep fork binary as `ui-offline.*`; never install over the official `ui` extension path used by `duckdb -ui`.
