#!/usr/bin/env python3
"""AVO scientific bench: runs the PRODUCTION engine (libavo_equine via ctypes) on reference signals and
reports the error against the known answer. Reproducible: fixed seeds, results written to JSON/CSV.

    python3 bench.py --lib path/to/libavo_equine.so --out bench_out
    python3 bench.py --lib ... --session SESSION.avo     # analyse a real session

No numerical code is duplicated here: Python only generates reference signals and compares.
"""
import argparse, ctypes, json, math, os, random, sys


def load(lib_path):
    lib = ctypes.CDLL(lib_path)
    lib.avo_eq_version.restype = ctypes.c_char_p
    lib.avo_eq_fundamental.restype = ctypes.c_double
    lib.avo_eq_fundamental.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int, ctypes.c_double, ctypes.c_double,
                                       ctypes.c_double, ctypes.POINTER(ctypes.c_double)]
    lib.avo_eq_analyse_files.argtypes = [ctypes.POINTER(ctypes.c_char_p), ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                                         ctypes.POINTER(ctypes.c_void_p)]
    lib.avo_eq_free.argtypes = [ctypes.c_void_p]
    return lib


def fundamental(lib, x, fs, fmin=0.6, fmax=3.5):
    arr = (ctypes.c_double * len(x))(*x)
    st = ctypes.c_double(0)
    f = lib.avo_eq_fundamental(arr, len(x), fs, fmin, fmax, ctypes.byref(st))
    return f, st.value


def stride_signal(f_stride, fs, secs, snr_db, unequal, seed):
    rnd = random.Random(seed)
    n = int(fs * secs)
    sig = [math.sin(2 * math.pi * 2 * f_stride * i / fs) + (0.45 * math.sin(2 * math.pi * f_stride * i / fs + 0.6) if unequal else 0)
           for i in range(n)]
    p = sum(v * v for v in sig) / n
    sd = math.sqrt(p / (10 ** (snr_db / 10))) if snr_db is not None else 0
    return [v + rnd.gauss(0, sd) for v in sig]


def experiment_cadence(lib, rows):
    """Error of the cycle frequency vs SNR and stride frequency (expected value known by construction)."""
    for f in (0.9, 1.2, 1.5, 1.9, 2.3):
        for snr in (20, 10, 5, 0):
            for unequal in (True, False):
                errs = []
                for seed in range(10):
                    x = stride_signal(f, 200, 6, snr, unequal, seed)
                    est, st = fundamental(lib, x, 200)
                    truth = f if unequal else 2 * f
                    if truth > 3.5:
                        continue
                    errs.append(abs(est - truth) if est > 0 else float('inf'))
                if not errs:
                    continue
                finite = [e for e in errs if math.isfinite(e)]
                rows.append({"experimento": "cadencia", "f_ciclo_hz": f if unequal else 2 * f, "snr_db": snr,
                             "dos_apoyos_distintos": unequal, "repeticiones": len(errs),
                             "sin_resultado": len(errs) - len(finite),
                             "error_medio_hz": sum(finite) / len(finite) if finite else None,
                             "error_max_hz": max(finite) if finite else None})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", required=True)
    ap.add_argument("--out", default="bench_out")
    ap.add_argument("--session", nargs="*")
    a = ap.parse_args()
    lib = load(a.lib)
    os.makedirs(a.out, exist_ok=True)
    if a.session:
        arr = (ctypes.c_char_p * len(a.session))(*[p.encode() for p in a.session])
        out = ctypes.c_void_p()
        rc = lib.avo_eq_analyse_files(arr, len(a.session), b"bench", 1, ctypes.byref(out))
        text = ctypes.cast(out, ctypes.c_char_p).value.decode()
        lib.avo_eq_free(out)
        open(os.path.join(a.out, "analysis.json"), "w").write(text)
        print("rc", rc, "->", os.path.join(a.out, "analysis.json"))
        return 0 if rc == 0 else 1
    rows = []
    experiment_cadence(lib, rows)
    report = {"motor": lib.avo_eq_version().decode(), "semillas": "0..9", "resultados": rows}
    json.dump(report, open(os.path.join(a.out, "bench_cadencia.json"), "w"), indent=1, ensure_ascii=False)
    with open(os.path.join(a.out, "bench_cadencia.csv"), "w") as f:
        keys = list(rows[0].keys())
        f.write(",".join(keys) + "\n")
        for r in rows:
            f.write(",".join("" if r[k] is None else str(r[k]) for k in keys) + "\n")
    worst = max((r["error_max_hz"] or 0) for r in rows if r["snr_db"] >= 5)
    fails = sum(r["sin_resultado"] for r in rows if r["snr_db"] >= 5)
    print(f"motor {report['motor']}: {len(rows)} condiciones; SNR>=5 dB: error máx {worst:.4f} Hz, sin resultado {fails}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
