#!/usr/bin/env python3
"""Regenerates the engine JSON fixtures consumed by the Kotlin and Android tests from their committed RAW files and
fails if they drift (numbers compared with a relative tolerance, the processing date is fixed).
    python3 check_fixtures.py path/to/avo_eq_cli [--update]"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
RES = os.path.join(ROOT, "core", "src", "test", "resources")
PAIRS = [(os.path.join(RES, "equine", "synthetic_session.avo"), os.path.join(RES, "equine", "synthetic_analysis.json")),
         (os.path.join(RES, "sample.avr"), os.path.join(RES, "equine", "sample_analysis.json"))]


def diff(a, b, path, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in set(a) | set(b):
            if k not in a or k not in b: out.append(f"{path}.{k}: clave solo en uno"); continue
            diff(a[k], b[k], f"{path}.{k}", out)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): out.append(f"{path}: longitud {len(a)} != {len(b)}"); return
        for i, (x, y) in enumerate(zip(a, b)): diff(x, y, f"{path}[{i}]", out)
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        if abs(a - b) > 1e-6 * max(1.0, abs(a), abs(b)): out.append(f"{path}: {a} != {b}")
    elif a != b:
        out.append(f"{path}: {a!r} != {b!r}")


def main():
    cli, update = sys.argv[1], "--update" in sys.argv
    bad = 0
    for raw, ref in PAIRS:
        with tempfile.TemporaryDirectory() as d:
            subprocess.run([cli, raw, "--out", d, "--series", "--when", "2026-10-24T00:00:00Z"], check=True, stdout=subprocess.DEVNULL)
            new = json.load(open(os.path.join(d, "analysis.json")))
        if update:
            json.dump(new, open(ref, "w"), ensure_ascii=False, separators=(",", ":")); print("actualizado", ref); continue
        out = []
        diff(json.load(open(ref)), new, "$", out)
        if out:
            bad += 1
            print(f"::error::{os.path.basename(ref)} no coincide con el motor actual ({len(out)} diferencias); regenerar con --update")
            for line in out[:20]: print("   ", line)
        else:
            print(f"OK {os.path.basename(ref)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
