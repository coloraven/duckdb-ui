> **中文 / Chinese:** [README.md](README.md)

# DuckDB UI Offline Fork (Overlay-only)

This repository **does not** vendor a full copy of [`duckdb/duckdb-ui`](https://github.com/duckdb/duckdb-ui).

At build time CI:

1. Checks out upstream `duckdb/duckdb-ui@main`
2. Applies this repo’s [`overlay/`](overlay/) (patched C++ / CMake)
3. Bundles [`scripts/theme`](scripts/theme) and [`scripts/fork`](scripts/fork) runtime injects
4. Builds and publishes the rolling tag [`offline-latest`](../../releases/tag/offline-latest)

Targets DuckDB **v1.5.5** (`-unsigned`). See [`OFFLINE.md`](OFFLINE.md).

## Layout

| Path | Role |
| --- | --- |
| `overlay/` | Files copied onto a clean upstream tree |
| `scripts/fork/` | Runtime injects (quoted Path, zh-CN dictionary) |
| `scripts/theme/` | Dark+ theme CSS |
| `scripts/start_ui.ps1` | Windows one-click install/start |
| `scripts/mirror_ui_assets.py` | Mirror `ui.duckdb.org` assets |
| `scripts/apply_overlay.*` | Apply overlay locally |
| `.github/workflows/offline-release.yml` | Watch upstream SHA → overlay build → release |

## Runtime model

- **Release install** (`start_ui.ps1`): no GitHub download if local extension + assets exist; use `-Fetch` to refresh
- **Assets**: local-first; miss → `ui_remote_url` → cache under `ui_assets_path`
- **CSP**: always same-origin for the browser (MotherDuck/Datadog blocked); server-side asset fill-in still works
- **`-AirGap` / `ui_offline=true`**: optional — never remote-fill assets (503 on miss)

```powershell
.\scripts\start_ui.ps1
.\scripts\start_ui.ps1 -Fetch
.\scripts\start_ui.ps1 -AirGap
```

See [`OFFLINE.md`](OFFLINE.md).

## Local build

```bash
git clone https://github.com/duckdb/duckdb-ui.git upstream-ui
git clone https://github.com/coloraven/duckdb-ui.git fork-overlay
bash fork-overlay/scripts/apply_overlay.sh upstream-ui
# then follow upstream build / extension-ci-tools
```

## Upstream sync

Scheduled jobs compare `duckdb/duckdb-ui` HEAD to the `Upstream-SHA:` marker in the `offline-latest` release notes. This repo no longer merges the full upstream tree into `main`.

## License

MIT for this fork’s scripts/overlay ([`LICENSE`](LICENSE)). Upstream and CDN UI assets remain under their original terms.
