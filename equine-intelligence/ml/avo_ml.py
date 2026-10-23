#!/usr/bin/env python3
"""AVO machine-learning infrastructure (no trained model is shipped: there are no labelled real data yet).

Dataset format (JSON Lines, one window per line) — produced from engine output + labels:
  {"caballo": "H001", "sesion": "S...", "sensor": "imu0", "t0": 12.0, "t1": 18.0,
   "rasgos": {"v_gnss": 3.4, "f_ciclo": 1.45, "fuerza": 0.82, "cv_intervalos": 0.04, "corr_ciclos": 0.93, "rms_rel": 2.1},
   "etiqueta": "TROTE", "calidad_etiqueta": "segura|dudosa", "calibracion": "sin_calibrar", "version_motor": "1.0.0-dev1"}

Labels file (produced by `label`): {"sesion": "...", "intervalos": [{"t0": 0, "t1": 30, "etiqueta": "PASO", "calidad": "segura", "autor": "..."}]}

Commands
  label    add / correct label intervals for a session (editable JSON, every change keeps author and date)
  build    join engine windows (cadencia.csv + gnss.csv) with labels -> dataset.jsonl
  train    reproducible training of an interpretable model (nearest centroid on standardised features)
  evaluate leave-one-horse-out + per-session results, confusion matrix, precision / recall / F1
  demo     builds a SYNTHETIC dataset to exercise the pipeline (results are NOT accuracy claims)
"""
import argparse, csv, datetime, json, math, os, random, sys

CLASSES = ["PARADO", "PASO", "TROTE", "GALOPE", "TRANSICION"]
FEATURES = ["v_gnss", "f_ciclo", "fuerza", "cv_intervalos", "corr_ciclos"]


# ------------------------------------------------------------------ labelling
def cmd_label(a):
    data = {"sesion": a.session, "intervalos": []}
    if os.path.exists(a.file):
        data = json.load(open(a.file))
    if a.remove is not None:
        data["intervalos"] = [x for i, x in enumerate(data["intervalos"]) if i != a.remove]
    if a.add:
        t0, t1, lab = a.add
        if lab not in CLASSES:
            sys.exit(f"etiqueta desconocida {lab}; use {CLASSES}")
        data["intervalos"].append({"t0": float(t0), "t1": float(t1), "etiqueta": lab, "calidad": a.quality,
                                   "autor": a.author, "fecha": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")})
    data["intervalos"].sort(key=lambda x: x["t0"])
    for x, y in zip(data["intervalos"], data["intervalos"][1:]):
        if y["t0"] < x["t1"]:
            print(f"aviso: intervalos solapados {x['t0']}-{x['t1']} y {y['t0']}-{y['t1']}")
    json.dump(data, open(a.file, "w"), indent=1, ensure_ascii=False)
    for i, x in enumerate(data["intervalos"]):
        print(i, x["t0"], x["t1"], x["etiqueta"], x["calidad"], x.get("autor", ""))


# ------------------------------------------------------------------ dataset
def cmd_build(a):
    labels = json.load(open(a.labels))
    gnss = list(csv.DictReader(open(os.path.join(a.analysis, "gnss.csv"))))
    cad = list(csv.DictReader(open(os.path.join(a.analysis, "cadencia.csv"))))
    meta = json.load(open(os.path.join(a.analysis, "analysis.json")))

    def speed_at(t):
        vs = [float(r["velocidad_m_s"]) for r in gnss if r["velocidad_m_s"] != "null" and abs(float(r["t_s"]) - t) <= 1.0]
        return sum(vs) / len(vs) if vs else None

    out = open(a.out, "a")
    n = 0
    for w in cad:
        if w["t_gnss_s"] == "null":
            continue          # window not mappable to GNSS time: cannot be joined with labels or speed
        t = float(w["t_gnss_s"])
        lab = next((x for x in labels["intervalos"] if x["t0"] <= t < x["t1"]), None)
        if not lab:
            continue
        def f(k):
            return None if w[k] == "null" else float(w[k])
        row = {"caballo": a.horse, "sesion": labels["sesion"], "sensor": "imu" + w["imu"], "t0": t - 3, "t1": t + 3,
               "rasgos": {"v_gnss": speed_at(t), "f_ciclo": f("frecuencia_hz"), "fuerza": f("fuerza"),
                          "cv_intervalos": f("cv_intervalos"), "corr_ciclos": f("correlacion_ciclos")},
               "etiqueta": lab["etiqueta"], "calidad_etiqueta": lab["calidad"], "calibracion": "sin_calibrar",
               "version_motor": meta.get("motor")}
        out.write(json.dumps(row, ensure_ascii=False) + "\n")
        n += 1
    print(f"{n} ventanas añadidas a {a.out}")


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
    model = fit(rows)
    model["entrenado_con"] = {"ventanas": len(rows), "caballos": sorted({r["caballo"] for r in rows}),
                              "fecha": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    json.dump(model, open(a.model, "w"), indent=1, ensure_ascii=False)
    print(f"modelo guardado en {a.model} ({len(rows)} ventanas)")


def cmd_evaluate(a):
    rows = [r for r in read_dataset(a.dataset) if r["calidad_etiqueta"] == "segura"]
    horses = sorted({r["caballo"] for r in rows})
    if len(horses) < 2:
        sys.exit("hace falta al menos 2 caballos para evaluar con caballo no visto")
    report = {"metodo": "dejar un caballo fuera (las ventanas de una sesión nunca se reparten entre entrenamiento y prueba)",
              "por_caballo": {}, "por_sesion": {}}
    allp = []
    for h in horses:
        train = [r for r in rows if r["caballo"] != h]
        test = [r for r in rows if r["caballo"] == h]
        m = fit(train)
        pairs = [(r["etiqueta"], predict(m, r)) for r in test]
        allp += pairs
        report["por_caballo"][h] = scores(pairs)
        for s in sorted({r["sesion"] for r in test}):
            report["por_sesion"][s] = scores([(r["etiqueta"], predict(m, r)) for r in test if r["sesion"] == s])
    report["global"] = scores(allp)
    json.dump(report, open(a.report, "w"), indent=1, ensure_ascii=False)
    g = report["global"]
    print(f"exactitud global (caballo no visto): {g['exactitud']:.3f} sobre {g['ventanas']} ventanas -> {a.report}")


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
    p.add_argument("--add", nargs=3, metavar=("T0", "T1", "ETIQUETA")); p.add_argument("--remove", type=int)
    p.add_argument("--quality", default="segura", choices=["segura", "dudosa"]); p.add_argument("--author", default="")
    p = sp.add_parser("build"); p.add_argument("--analysis", required=True); p.add_argument("--labels", required=True)
    p.add_argument("--horse", required=True); p.add_argument("--out", required=True)
    p = sp.add_parser("train"); p.add_argument("--dataset", required=True); p.add_argument("--model", required=True)
    p = sp.add_parser("evaluate"); p.add_argument("--dataset", required=True); p.add_argument("--report", required=True)
    p = sp.add_parser("demo"); p.add_argument("--out", required=True)
    a = ap.parse_args()
    {"label": cmd_label, "build": cmd_build, "train": cmd_train, "evaluate": cmd_evaluate, "demo": cmd_demo}[a.cmd](a)


if __name__ == "__main__":
    main()
