> **中文 / Chinese:** [README.md](README.md)

# DuckDB UI Offline Fork (Overlay-only)

This repository **does not** vendor a full copy of [`duckdb/duckdb-ui`](https://github.com/duckdb/duckdb-ui).

At build time CI:

1. Checks out upstream `duckdb/duckdb-ui@main`
2. Applies this repo’s [`overlay/`](overlay/) (patched C++ / CMake)
3. Bundles [`scripts/theme`](scripts/theme) and [`scripts/fork`](scripts/fork) runtime injects
4. Builds and publishes the rolling tag [`offline-latest`](../../releases/tag/offline-latest)

Targets DuckDB **v1.5.5**: use a matching CLI and start with **`-unsigned`** (this extension is unsigned). See [`OFFLINE.md`](OFFLINE.md).

Rolling release tag: [`offline-latest`](../../releases/tag/offline-latest) (notes include `Upstream-SHA:` for that build).

## Layout

| Path | Role |
| --- | --- |
| `overlay/` | Files copied onto a clean upstream tree |
| `scripts/fork/` | Runtime injects (quoted Path, zh-CN dictionary) |
| `scripts/theme/` | Dark+ theme CSS |
| `scripts/start_ui.ps1` | Windows one-click install/start (can pull the release) |
| `scripts/install_ui_assets.sh` | Linux/macOS: install from a downloaded tar/zip |
| `scripts/mirror_ui_assets.py` | Mirror `ui.duckdb.org` assets |
| `scripts/apply_overlay.*` | Apply overlay locally |
| `.github/workflows/offline-release.yml` | Watch upstream SHA → overlay build → release |

## Resource model (same as release notes)

| Layer | Default |
| --- | --- |
| **Release install** (`start_ui.ps1`) | Start only if local extension + assets exist; download on miss or `-Fetch` |
| **Runtime assets** | Local-first; miss → extension fetches `ui_remote_url` and caches; browser CSP always blocks MotherDuck/Datadog |
| **Air-gap** (optional) | `SET ui_offline=true` / `start_ui.ps1 -AirGap` → miss returns 503 |

Artifacts are named **`ui-offline.*`** and never overwrite official `ui.duckdb_extension`. Manual `LOAD` requires copying the fork binary into a private temp dir as **`ui.duckdb_extension`** (entrypoint = file stem); `start_ui.ps1` does this for you.

```powershell
.\scripts\start_ui.ps1
.\scripts\start_ui.ps1 -Fetch
.\scripts\start_ui.ps1 -AirGap
.\scripts\start_ui.ps1 -NoStart
```

Open **`http://127.0.0.1:4213/`** (use `127.0.0.1`, not `localhost`, on Windows).

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
