#!/usr/bin/env python3
"""AVO machine-learning infrastructure (no trained model is shipped: there are no labelled real data yet).

Dataset format (JSON Lines, one window per line) — produced from engine output + labels:
  {"caballo": "H001", "sesion": "S...", "sensor": "imu0", "t0": 12.0, "t1": 18.0,
   "rasgos": {"v_gnss": 3.4, "f_ciclo": 1.45, "fuerza": 0.82, "cv_intervalos": 0.04, "corr_ciclos": 0.93, "rms_rel": 2.1},
   "etiqueta": "TROTE", "calidad_etiqueta": "segura|dudosa", "calibracion": "sin_calibrar", "version_motor": "1.0.0-dev1"}

Labels file (produced by `label`): {"sesion": "...", "intervalos": [{"t0": 0, "t1": 30, "etiqueta": "PASO", "calidad": "segura", "autor": "..."}]}

Commands
  label    add / correct (--edit, keeps history) / remove intervals; horse and session association; intervals can be
           selected from an engine segment (--from-analysis analysis.json --segment N --label-as TROTE)
  build    join engine windows (analysis.json v2, series_cincha) with labels -> dataset.jsonl (requires the horse)
  export   dataset.jsonl -> CSV
  train    reproducible training of an interpretable model (nearest centroid on standardised features)
  evaluate leave-one-horse-out (--split caballo) or leave-one-session-out (--split sesion), confusion, precision / recall / F1
  train refuses synthetic-only datasets unless --allow-synthetic (pipeline tests; the model is marked "definitivo": false)
  demo     builds a SYNTHETIC dataset to exercise the pipeline (results are NOT accuracy claims)
"""
import argparse, csv, datetime, json, math, os, random, sys

CLASSES = ["PARADO", "PASO", "TROTE", "GALOPE", "TRANSICION"]
FEATURES = ["v_gnss", "f_ciclo", "fuerza", "cv_intervalos", "corr_ciclos"]


# ------------------------------------------------------------------ labelling
def cmd_label(a):
    data = {"sesion": a.session, "caballo": a.horse, "intervalos": []}
    if os.path.exists(a.file):
        data = json.load(open(a.file))
    if a.horse:
        data["caballo"] = a.horse
    if a.session:
        data["sesion"] = a.session
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if a.from_analysis is not None:
        # select an interval from a segment of the engine result (rendimiento.segmentos[id])
        an = json.load(open(a.from_analysis))
        seg = next((x for x in an["rendimiento"]["segmentos"] if x["id"] == a.segment), None)
        if not seg:
            sys.exit(f"no existe el tramo {a.segment} en {a.from_analysis}")
        if not a.label_as:
            sys.exit("indique --label-as con la etiqueta (el aire del motor no se copia automáticamente)")
        a.add = (seg["t0"], seg["t1"], a.label_as)
        data["sesion"] = data.get("sesion") or an["sesion"]["id"]
    if a.edit is not None:
        idx, lab = a.edit
        idx = int(idx)
        if lab not in CLASSES:
            sys.exit(f"etiqueta desconocida {lab}; use {CLASSES}")
        it = data["intervalos"][idx]
        it.setdefault("historial", []).append({"etiqueta": it["etiqueta"], "autor": it.get("autor", ""), "fecha": it.get("fecha", "")})
        it.update({"etiqueta": lab, "autor": a.author, "fecha": now, "calidad": a.quality})
    if a.remove is not None:
        data["intervalos"] = [x for i, x in enumerate(data["intervalos"]) if i != a.remove]
    if a.add:
        t0, t1, lab = a.add
        if lab not in CLASSES:
            sys.exit(f"etiqueta desconocida {lab}; use {CLASSES}")
        data["intervalos"].append({"t0": float(t0), "t1": float(t1), "etiqueta": lab, "calidad": a.quality,
                                   "autor": a.author, "fecha": now})
    data["intervalos"].sort(key=lambda x: x["t0"])
    for x, y in zip(data["intervalos"], data["intervalos"][1:]):
        if y["t0"] < x["t1"]:
            print(f"aviso: intervalos solapados {x['t0']}-{x['t1']} y {y['t0']}-{y['t1']}")
    json.dump(data, open(a.file, "w"), indent=1, ensure_ascii=False)
    for i, x in enumerate(data["intervalos"]):
        print(i, x["t0"], x["t1"], x["etiqueta"], x["calidad"], x.get("autor", ""))


# ------------------------------------------------------------------ dataset
def cmd_build(a):
    """Joins engine windows with labels. Accepts the v2 analysis JSON (series_cincha) or the v1 CSV folder."""
    labels = json.load(open(a.labels))
    horse = a.horse or labels.get("caballo")
    if not horse:
        sys.exit("falta el caballo (--horse o 'caballo' en el fichero de etiquetas): necesario para separar por caballo")
    src = a.analysis
    if os.path.isdir(src):
        src = os.path.join(src, "analysis.json")
    meta = json.load(open(src))
    sc = meta.get("series_cincha")
    if not sc:
        sys.exit("el análisis no tiene series_cincha: ejecute el motor con --series (y la sesión debe tener datos de cincha)")
    out = open(a.out, "a")
    n = skipped = 0
    for i, t in enumerate(sc["t"]):
        if t is None or sc["estado"][i] != "OK":
            skipped += 1
            continue
        lab = next((x for x in labels["intervalos"] if x["t0"] <= t < x["t1"]), None)
        if not lab:
            continue
        row = {"caballo": horse, "sesion": labels.get("sesion") or meta["sesion"]["id"], "sensor": "imu%d" % sc["imu"][i], "t0": t - 3, "t1": t + 3,
               "rasgos": {"v_gnss": sc["velocidad"][i], "f_ciclo": sc["cadencia_hz"][i], "fuerza": None,
                          "cv_intervalos": sc["cv_intervalos"][i], "corr_ciclos": sc["correlacion_ciclos"][i]},
               "etiqueta": lab["etiqueta"], "calidad_etiqueta": lab["calidad"], "calibracion": "sin_calibrar",
               "version_motor": meta.get("motor"), "sintetico": meta["sesion"]["id"].startswith("SINTETICA")}
        out.write(json.dumps(row, ensure_ascii=False) + "\n")
        n += 1
    print(f"{n} ventanas añadidas a {a.out} ({skipped} ventanas sin fusión válida omitidas)")


def cmd_export(a):
    rows = read_dataset(a.dataset)
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["caballo", "sesion", "sensor", "t0", "t1"] + FEATURES + ["etiqueta", "calidad_etiqueta", "version_motor", "sintetico"])
        for r in rows:
            w.writerow([r["caballo"], r["sesion"], r["sensor"], r["t0"], r["t1"]] + [r["rasgos"].get(k) for k in FEATURES] +
                       [r["etiqueta"], r["calidad_etiqueta"], r.get("version_motor"), r.get("sintetico", False)])
    print(f"{len(rows)} filas -> {a.out}")


def read_dataset(path):
    return [json.loads(l) for l in open(path) if l.strip()]


# ------------------------------------------------------------------ model: nearest centroid on standardised features
def vec(row):
    return [row["rasgos"].get(k) for k in FEATURES]


def fit(rows):
    cols = list(zip(*[vec(r) for r in rows]))
    mu = [sum(v for v in c if v is not None) / max(1, sum(v is not None for v in c)) for c in cols]
    sd = []
    for c, m in zip(cols, mu):
        vals = [v for v in c if v is not None]
        s = math.sqrt(sum((v - m) ** 2 for v in vals) / max(1, len(vals) - 1)) if len(vals) > 1 else 1.0
        sd.append(s if s > 1e-9 else 1.0)
    cent = {}
    for cl in CLASSES:
        rs = [vec(r) for r in rows if r["etiqueta"] == cl]
        if not rs:
            continue
        cent[cl] = [sum(((x[i] if x[i] is not None else mu[i]) - mu[i]) / sd[i] for x in rs) / len(rs) for i in range(len(FEATURES))]
    return {"tipo": "centroide_mas_cercano", "rasgos": FEATURES, "media": mu, "desv": sd, "centroides": cent}


def predict(model, row):
    z = [(((v if v is not None else m) - m) / s) for v, m, s in zip(vec(row), model["media"], model["desv"])]
    return min(model["centroides"], key=lambda c: sum((a - b) ** 2 for a, b in zip(z, model["centroides"][c])))


def scores(pairs):
    labels = sorted({t for t, _ in pairs} | {p for _, p in pairs})
    cm = {t: {p: 0 for p in labels} for t in labels}
    for t, p in pairs:
        cm[t][p] += 1
    per = {}
    for c in labels:
        tp = cm[c][c]
        fp = sum(cm[t][c] for t in labels if t != c)
        fn = sum(cm[c][p] for p in labels if p != c)
        pr = tp / (tp + fp) if tp + fp else None
        rc = tp / (tp + fn) if tp + fn else None
        f1 = 2 * pr * rc / (pr + rc) if pr and rc else None
        per[c] = {"precision": pr, "recall": rc, "f1": f1, "soporte": tp + fn}
    acc = sum(cm[c][c] for c in labels) / max(1, len(pairs))
    return {"matriz_confusion": cm, "por_clase": per, "exactitud": acc, "ventanas": len(pairs)}


def cmd_train(a):
    rows = [r for r in read_dataset(a.dataset) if r["calidad_etiqueta"] == "segura"]
    synthetic = all(r.get("sintetico") or r.get("version_motor") == "SINTETICO" for r in rows) if rows else True
    if synthetic and not a.allow_synthetic:
        sys.exit("el dataset es sintético: no se entrena un modelo definitivo (use --allow-synthetic solo para probar la canalización)")
    model = fit(rows)
    model["definitivo"] = not synthetic
    model["entrenado_con"] = {"ventanas": len(rows), "caballos": sorted({r["caballo"] for r in rows}), "sesiones": sorted({r["sesion"] for r in rows}),
                              "fecha": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    json.dump(model, open(a.model, "w"), indent=1, ensure_ascii=False)
    print(f"modelo guardado en {a.model} ({len(rows)} ventanas)")


def cmd_evaluate(a):
    rows = [r for r in read_dataset(a.dataset) if r["calidad_etiqueta"] == "segura"]
    key = "caballo" if a.split == "caballo" else "sesion"
    groups = sorted({r[key] for r in rows})
    if len(groups) < 2:
        sys.exit(f"hace falta al menos 2 valores de '{key}' para evaluar con datos no vistos")
    report = {"metodo": f"dejar un {key} fuera (las ventanas de una sesión nunca se reparten entre entrenamiento y prueba)",
              "sintetico": any(r.get("sintetico") or r.get("version_motor") == "SINTETICO" for r in rows),
              "por_caballo": {}, "por_sesion": {}}
    allp = []
    for h in groups:
        train = [r for r in rows if r[key] != h]
        test = [r for r in rows if r[key] == h]
        m = fit(train)
        pairs = [(r["etiqueta"], predict(m, r)) for r in test]
        allp += pairs
        report["por_caballo" if key == "caballo" else "por_sesion"][h] = scores(pairs)
        if key == "caballo":
            for s in sorted({r["sesion"] for r in test}):
                report["por_sesion"][s] = scores([(r["etiqueta"], predict(m, r)) for r in test if r["sesion"] == s])
    report["global"] = scores(allp)
    json.dump(report, open(a.report, "w"), indent=1, ensure_ascii=False)
    g = report["global"]
    aviso = " (DATOS SINTÉTICOS: no es exactitud real)" if report["sintetico"] else ""
    print(f"exactitud global ({key} no visto): {g['exactitud']:.3f} sobre {g['ventanas']} ventanas{aviso} -> {a.report}")


def cmd_demo(a):
    """SYNTHETIC data only, to exercise the pipeline. Its numbers say nothing about real horses."""
    rnd = random.Random(1)
    proto = {"PARADO": (0.1, 0.0, 0.1), "PASO": (1.6, 0.95, 0.8), "TROTE": (3.4, 1.45, 0.85), "GALOPE": (7.5, 1.9, 0.8)}
    with open(a.out, "w") as f:
        for h in ["SINT_A", "SINT_B", "SINT_C"]:
            for cl, (v, fr, st) in proto.items():
                for i in range(40):
                    row = {"caballo": h, "sesion": f"{h}_S1", "sensor": "imu0", "t0": i * 2, "t1": i * 2 + 6,
                           "rasgos": {"v_gnss": max(0, rnd.gauss(v, 0.15 * v + 0.05)), "f_ciclo": None if cl == "PARADO" else rnd.gauss(fr, 0.08),
                                      "fuerza": rnd.gauss(st, 0.05), "cv_intervalos": abs(rnd.gauss(0.05, 0.02)), "corr_ciclos": rnd.gauss(0.9, 0.04)},
                           "etiqueta": cl, "calidad_etiqueta": "segura", "calibracion": "sin_calibrar", "version_motor": "SINTETICO"}
                    f.write(json.dumps(row) + "\n")
    print(f"dataset SINTÉTICO en {a.out} (solo para probar la canalización)")


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("label"); p.add_argument("file"); p.add_argument("--session", default="")
    p.add_argument("--horse", default=""); p.add_argument("--edit", nargs=2, metavar=("INDICE", "ETIQUETA"))
    p.add_argument("--from-analysis"); p.add_argument("--segment", type=int); p.add_argument("--label-as")
    p.add_argument("--add", nargs=3, metavar=("T0", "T1", "ETIQUETA")); p.add_argument("--remove", type=int)
    p.add_argument("--quality", default="segura", choices=["segura", "dudosa"]); p.add_argument("--author", default="")
    p = sp.add_parser("build"); p.add_argument("--analysis", required=True); p.add_argument("--labels", required=True)
    p.add_argument("--horse", default=""); p.add_argument("--out", required=True)
    p = sp.add_parser("export"); p.add_argument("--dataset", required=True); p.add_argument("--out", required=True)
    p = sp.add_parser("train"); p.add_argument("--dataset", required=True); p.add_argument("--model", required=True)
    p.add_argument("--allow-synthetic", action="store_true")
    p = sp.add_parser("evaluate"); p.add_argument("--dataset", required=True); p.add_argument("--report", required=True)
    p.add_argument("--split", choices=["caballo", "sesion"], default="caballo")
    p = sp.add_parser("demo"); p.add_argument("--out", required=True)
    a = ap.parse_args()
    {"label": cmd_label, "build": cmd_build, "export": cmd_export, "train": cmd_train, "evaluate": cmd_evaluate, "demo": cmd_demo}[a.cmd](a)


if __name__ == "__main__":
    main()
