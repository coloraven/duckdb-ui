#!/usr/bin/env python3
"""Fail if a Windows PE imports OpenSSL DLLs (libssl/libcrypto)."""
from __future__ import annotations

import struct
import sys
from pathlib import Path


def list_dll_imports(path: Path) -> list[str]:
    data = path.read_bytes()
    if data[:2] != b"MZ":
        raise SystemExit(f"not an MZ file: {path}")
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_off : pe_off + 4] != b"PE\0\0":
        raise SystemExit(f"not a PE file: {path}")
    num_sections = struct.unpack_from("<H", data, pe_off + 6)[0]
    optional_header_size = struct.unpack_from("<H", data, pe_off + 20)[0]
    opt_off = pe_off + 24
    magic = struct.unpack_from("<H", data, opt_off)[0]
    pe32plus = magic == 0x20B
    dd_off = opt_off + (112 if pe32plus else 96)
    import_rva = struct.unpack_from("<I", data, dd_off + 8)[0]
    sec_off = opt_off + optional_header_size
    sections = []
    for i in range(num_sections):
        off = sec_off + i * 40
        vsize = struct.unpack_from("<I", data, off + 8)[0]
        va = struct.unpack_from("<I", data, off + 12)[0]
        rawsize = struct.unpack_from("<I", data, off + 16)[0]
        rawptr = struct.unpack_from("<I", data, off + 20)[0]
        sections.append((va, vsize, rawptr, rawsize))

    def rva_to_off(rva: int) -> int:
        for va, vsize, rawptr, rawsize in sections:
            if va <= rva < va + max(vsize, rawsize):
                return rawptr + (rva - va)
        raise ValueError(f"rva not found: {rva:#x}")

    dlls: list[str] = []
    if not import_rva:
        return dlls
    off = rva_to_off(import_rva)
    while True:
        lookup, _ts, _fwd, name_rva, iat = struct.unpack_from("<IIIII", data, off)
        if lookup == 0 and name_rva == 0 and iat == 0:
            break
        name = data[rva_to_off(name_rva) :].split(b"\0", 1)[0].decode("ascii", "replace")
        dlls.append(name)
        off += 20
    return dlls


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <file.duckdb_extension>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    dlls = list_dll_imports(path)
    print("imports:")
    for d in dlls:
        print(" ", d)
    bad = [d for d in dlls if "ssl" in d.lower() or "crypto" in d.lower()]
    if bad:
        print("ERROR: dynamic OpenSSL imports:", bad, file=sys.stderr)
        return 1
    print("OK: no OpenSSL DLL imports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
