#!/usr/bin/env python3
"""Mirror DuckDB UI static assets from the public CDN for offline use.

Strategy (best-effort, conservative):
  1) Seed: /, /index.html, /config, /favicon.svg
  2) Parse HTML for src/href
  3) Parse CSS for url(...)
  4) Parse JS only for clearly static paths (hatchling.*, hashed font/js/css/wasm)
  5) Optional Playwright capture of real network responses
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_REMOTE = "https://ui.duckdb.org"

HREF_SRC_RE = re.compile(r"""(?:src|href)\s*=\s*["']([^"']+)["']""", re.I)
CSS_URL_RE = re.compile(r"""url\((['"]?)([^'")]+)\1\)""", re.I)
# Conservative JS/HTML quoted static paths.
STATIC_PATH_RE = re.compile(
    r"""["'`](/(?:hatchling\.[A-Za-z0-9._-]+|(?:assets/)?[A-Za-z0-9_-]+\.(?:js|mjs|css|woff2?|ttf|png|jpe?g|svg|webp|wasm|map|json|txt)))["'`]"""
)
ABS_REMOTE_RE = re.compile(
    r"""https://ui\.duckdb\.org(/[A-Za-z0-9._/-]+\.(?:js|mjs|css|woff2?|ttf|png|jpe?g|svg|webp|wasm|map|json|txt))"""
)


def normalize_url(remote: str, raw: str) -> str | None:
    raw = raw.strip()
    if not raw or raw.startswith(("data:", "blob:", "mailto:", "javascript:")):
        return None
    if raw.startswith("//"):
        raw = "https:" + raw
    absolute = urllib.parse.urljoin(remote.rstrip("/") + "/", raw)
    parsed = urllib.parse.urlparse(absolute)
    remote_parsed = urllib.parse.urlparse(remote)
    if parsed.scheme not in ("http", "https"):
        return None
    if parsed.netloc != remote_parsed.netloc:
        return None
    path = parsed.path or "/"
    # Reject obvious non-asset junk.
    if ".." in path:
        return None
    return urllib.parse.urlunparse(
        (remote_parsed.scheme, remote_parsed.netloc, path, "", "", "")
    )


def local_path_for(url: str, out_dir: Path) -> Path:
    parsed = urllib.parse.urlparse(url)
    rel = parsed.path.lstrip("/")
    if not rel or rel.endswith("/"):
        rel = (rel + "index.html") if rel else "index.html"
    return out_dir / rel


def fetch(url: str, timeout: float = 60.0) -> tuple[int, bytes, str]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "duckdb-ui-offline-mirror/1.1",
            "Accept": "*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        status = getattr(resp, "status", 200) or 200
        content_type = resp.headers.get("Content-Type", "")
        return status, resp.read(), content_type


def extract_refs(url: str, body: bytes, content_type: str, remote: str) -> set[str]:
    found: set[str] = set()
    text = body.decode("utf-8", errors="ignore")
    ct = content_type.lower()
    path = urllib.parse.urlparse(url).path.lower()

    def add(raw: str) -> None:
        norm = normalize_url(remote, raw)
        if norm:
            found.add(norm)

    is_html = "html" in ct or path.endswith((".html", ".htm")) or path in ("/", "")
    is_css = "css" in ct or path.endswith(".css")
    is_js = "javascript" in ct or path.endswith((".js", ".mjs"))

    if is_html:
        for match in HREF_SRC_RE.finditer(text):
            add(match.group(1))
    if is_css:
        for match in CSS_URL_RE.finditer(text):
            add(match.group(2))
    if is_html or is_js or is_css:
        for match in STATIC_PATH_RE.finditer(text):
            add(match.group(1))
        for match in ABS_REMOTE_RE.finditer(text):
            add(match.group(1))
    return found


def patch_js_for_offline(body: bytes) -> bytes:
    """Skip MotherDuck Auth0 silent login so local HTTP UI paints immediately.

    Upstream waits authorizeTimeoutInSeconds (default 60) for an Auth0 iframe.
    For air-gapped/local HTTP mode we force silent auth to fail instantly and
    fall through to unauthenticated mode.
    """
    # Unique marker inside the Auth0SilentSignIn span: replace getTokenSilently
    # with an immediate false so we never open the MotherDuck iframe.
    old = b'runInSpanAsync("Auth0SilentSignIn",async Cr=>{const Mr=await dt();'
    new = b'runInSpanAsync("Auth0SilentSignIn",async Cr=>{const Mr=!1;'
    if old in body:
        body = body.replace(old, new, 1)
    # Belt-and-suspenders if the marker above drifts in a future CDN bundle.
    body = body.replace(b"authorizeTimeoutInSeconds||60", b"authorizeTimeoutInSeconds||1")
    body = body.replace(
        b',pt=60)=>new Promise((ht,ft)=>{const Et=window.document.createElement("iframe")',
        b',pt=1)=>new Promise((ht,ft)=>{const Et=window.document.createElement("iframe")',
    )
    return body


def mirror(remote: str, out_dir: Path, use_playwright: bool, max_assets: int) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    seeds = [
        "/",
        "/index.html",
        "/config",
        "/version",
        "/manifest",
        "/favicon.svg",
        "/favicon_duckdb.svg",
        "/news",
        "/settings",
    ]
    queue: list[str] = []
    seen: set[str] = set()
    saved: list[dict] = []
    failed: list[dict] = []

    def enqueue(url: str | None) -> None:
        if not url or url in seen:
            return
        seen.add(url)
        queue.append(url)

    for seed in seeds:
        enqueue(normalize_url(remote, seed))

    if use_playwright:
        try:
            from playwright.sync_api import sync_playwright  # type: ignore
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] Playwright unavailable: {exc}", file=sys.stderr)
        else:
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True)
                page = browser.new_page()
                captured: set[str] = set()

                def on_response(response) -> None:  # noqa: ANN001
                    try:
                        norm = normalize_url(remote, response.url)
                        if norm:
                            captured.add(norm)
                    except Exception:
                        return

                page.on("response", on_response)
                page.goto(remote.rstrip("/") + "/", wait_until="networkidle", timeout=120000)
                for route in ("/", "/news", "/settings"):
                    try:
                        page.goto(
                            remote.rstrip("/") + route,
                            wait_until="networkidle",
                            timeout=60000,
                        )
                    except Exception:
                        pass
                browser.close()
                for url in sorted(captured):
                    enqueue(url)
                print(f"[info] Playwright captured {len(captured)} URLs")

    while queue and len(saved) < max_assets:
        url = queue.pop(0)
        dest = local_path_for(url, out_dir)
        try:
            status, body, content_type = fetch(url)
            if status >= 400:
                failed.append({"url": url, "status": status})
                continue
            if "javascript" in content_type.lower() or dest.suffix in (".js", ".mjs"):
                body = patch_js_for_offline(body)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(body)
            saved.append(
                {
                    "url": url,
                    "path": str(dest.relative_to(out_dir)),
                    "bytes": len(body),
                    "sha256": hashlib.sha256(body).hexdigest(),
                    "content_type": content_type,
                }
            )
            print(f"[ok] {url} -> {dest.relative_to(out_dir)} ({len(body)} bytes)")
            for ref in extract_refs(url, body, content_type, remote):
                enqueue(ref)
            time.sleep(0.02)
        except urllib.error.HTTPError as exc:
            failed.append({"url": url, "status": exc.code, "error": str(exc)})
            print(f"[fail] {url}: HTTP {exc.code}", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001
            failed.append({"url": url, "error": str(exc)})
            print(f"[fail] {url}: {exc}", file=sys.stderr)

    root_index = out_dir / "index.html"
    if not root_index.exists():
        try:
            _, body, _ = fetch(remote.rstrip("/") + "/")
            root_index.write_bytes(body)
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] could not synthesize index.html: {exc}", file=sys.stderr)

    manifest = {
        "remote": remote,
        "generated_at_unix": int(time.time()),
        "asset_count": len(saved),
        "failed_count": len(failed),
        "assets": saved,
        "failed": failed,
    }
    (out_dir / "mirror-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--remote", default=DEFAULT_REMOTE)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--playwright", action="store_true")
    parser.add_argument("--max-assets", type=int, default=500)
    args = parser.parse_args()

    manifest = mirror(args.remote, args.out, args.playwright, args.max_assets)
    print(
        f"[done] saved={manifest['asset_count']} failed={manifest['failed_count']} out={args.out}"
    )
    return 0 if manifest["asset_count"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
