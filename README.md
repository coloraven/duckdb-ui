> **English:** [README.en.md](README.en.md)

# DuckDB UI 离线 Fork（仅 Overlay）

本仓库**不再复刻** [`duckdb/duckdb-ui`](https://github.com/duckdb/duckdb-ui) 的完整源码。

CI 在构建时会：

1. 检出上游 `duckdb/duckdb-ui@main`
2. 将本仓 [`overlay/`](overlay/) 覆盖上去（魔改 C++ / CMake）
3. 附带 [`scripts/theme`](scripts/theme)、[`scripts/fork`](scripts/fork) 静态注入资源
4. 编译并发布滚动标签 [`offline-latest`](../../releases/tag/offline-latest)

面向 DuckDB **v1.5.5**（`-unsigned`）。细节见 [`OFFLINE.md`](OFFLINE.md)。

---

## 仓库里有什么

| 路径 | 说明 |
| --- | --- |
| `overlay/` | 相对上游的补丁文件（完整文件覆盖，不是 git submodule） |
| `scripts/fork/` | 运行时注入：路径去引号、zh-CN 词表 |
| `scripts/theme/` | Dark+ 主题 CSS |
| `scripts/start_ui.ps1` | Windows 一键安装/启动 |
| `scripts/mirror_ui_assets.py` | 镜像 `ui.duckdb.org` 静态资源 |
| `scripts/apply_overlay.sh` / `.ps1` | 本地把 overlay 打到上游检出 |
| `.github/workflows/offline-release.yml` | 监测上游 SHA → 叠加构建 → 发布 |

上游原仓代码（`src/` 全量、`ts/`、`third_party/` 等）**不在本仓保留**。

---

## 魔改能力（注入 / 扩展）

- **Release 本地优先**：`start_ui.ps1` 无参只启动；缺扩展/静态资源或 `-Fetch` 才拉 `offline-latest`
- **运行时 asset**：本地优先 → miss 回源 `ui_remote_url` 并写入缓存；浏览器侧 CSP 始终拦截 MotherDuck/Datadog
- **`ui_offline` / `-AirGap`**：可选气隙（miss 不再回源，503）；日常不必开
- Windows `ui_local_host=127.0.0.1`
- 主题切换（Dark+ token，非 invert）
- 界面汉化（`dd-ui-fork-i18n-zh-CN.json`）
- 添加数据库 Path 支持 `"..."` / `'...'`

发布物名为 **`ui-offline.*`**，不覆盖官方 `ui.duckdb_extension`。

---

## 快速开始（Windows）

```powershell
curl.exe -fsSL -o start_ui.ps1 https://gh-proxy.com/https://raw.githubusercontent.com/coloraven/duckdb-ui/main/scripts/start_ui.ps1
powershell -ExecutionPolicy Bypass -File .\start_ui.ps1
powershell -ExecutionPolicy Bypass -File .\start_ui.ps1 -Fetch    # 强制刷新 offline-latest
powershell -ExecutionPolicy Bypass -File .\start_ui.ps1 -AirGap   # 气隙：asset miss 不回源
```

本地预览主题/汉化（不编译扩展）：

```powershell
.\scripts\dev_theme.ps1 -CssOnly
```

---

## 本地编译（开发 overlay）

```bash
git clone https://github.com/duckdb/duckdb-ui.git upstream-ui
git clone https://github.com/coloraven/duckdb-ui.git fork-overlay
bash fork-overlay/scripts/apply_overlay.sh upstream-ui
# 再按上游 README / extension-ci-tools 流程 make release
```

Windows：

```powershell
.\scripts\apply_overlay.ps1 -Target C:\src\duckdb-ui-upstream
```

改完 `overlay/` 或 `scripts/fork|theme` 后 push `main`，CI 会重新叠加上游并发布。

---

## 上游同步策略

- **定时**：对比 `duckdb/duckdb-ui` 最新 commit 与 `offline-latest` 发布说明中的 `Upstream-SHA:`；有变化才构建
- **本仓不再** `git merge` 上游整树，避免无关历史/冲突把 overlay 冲掉
- 若上游改动与 `overlay/` 文件冲突，需在本仓更新对应 overlay 文件后重编

---

## License

本仓自有脚本与 overlay 补丁沿用 MIT（见 [`LICENSE`](LICENSE)）。上游 `duckdb/duckdb-ui` 及其依赖仍归原项目许可；静态前端壳来自 `ui.duckdb.org` 已发布资源。
