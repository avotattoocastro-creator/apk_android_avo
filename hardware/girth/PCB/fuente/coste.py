"""Coste de componentes por placa, REV A (ESP32-C6) frente a REV B (ESP32-C3), con los precios y el tipo
(Basic/Extended) que JLCPCB devolvió en el CI (out_stock/stock_jlc.json). Escribe out_stock/COSTE.md.

Supuestos (tarifas de montaje de JLCPCB, a revisar el día del pedido): 3 US$ por cada referencia «Extended»
distinta y pedido; montaje estándar con preparación fija igual en las dos revisiones (no cambia la comparación).
Las piezas a mano (pads de hilo/prueba) y las DNP no cuentan. La PCB desnuda es la misma en las dos revisiones.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ST = json.load(open(os.path.join(HERE, "..", "out_stock", "stock_jlc.json"), encoding="utf-8"))
EXT_FEE = 3.0


def price(code, qty):
    p = ST["parts"].get(code) or {}
    best = None
    for n, v in p.get("prices") or []:
        if n is not None and qty >= n:
            best = v
    return best, p


def bom(path, n_boards):
    parts = [p for p in json.load(open(path, encoding="utf-8")) if not p["dnp"] and not p["no_assembly"]]
    rows, total, ext, missing, nostock = {}, 0.0, set(), [], []
    for p in parts:
        rows.setdefault(p["lcsc"], []).append(p)
    lines = []
    for code, ps in sorted(rows.items(), key=lambda kv: -len(kv[1])):
        q = len(ps) * n_boards
        pr, info = price(code, q)
        if pr is None:
            missing.append(code)
            continue
        if info.get("library") != "base":
            ext.add(code)
        if not info.get("stock") or info["stock"] < q:
            nostock.append("%s %s (%s uds.)" % (code, info.get("mpn"), info.get("stock")))
        total += pr * len(ps)
        lines.append((code, info.get("mpn"), len(ps), pr, info.get("library"), info.get("stock")))
    return dict(total=total, ext=sorted(ext), missing=missing, nostock=nostock, lines=lines, n=len(parts))


def main():
    out = []
    a_path = os.path.join(HERE, "..", "..", "PCB_REV_A_C6", "kicad", "piezas.json")
    b_path = os.path.join(HERE, "..", "kicad", "piezas.json")
    out.append("# Coste de componentes por placa: REV A (ESP32-C6) frente a REV B (ESP32-C3)")
    out.append("")
    out.append("Precios, existencias y tipo consultados a JLCPCB desde el CI el **%s**. " % ST["date_utc"] +
               "Supuesto: %.0f US$ por referencia «Extended» distinta y pedido. La PCB desnuda y la preparación del "
               "montaje son iguales en las dos revisiones y no se incluyen." % EXT_FEE)
    out.append("")
    out.append("| Pedido | REV A componentes | REV A Extended (uds. · cargo/placa) | REV A total/placa | "
               "REV B componentes | REV B Extended | REV B total/placa | Reducción |")
    out.append("|---|---|---|---|---|---|---|---|")
    res = {}
    for n in (5, 10, 30):
        A = bom(a_path, n); B = bom(b_path, n)
        ta = A["total"] + EXT_FEE * len(A["ext"]) / n
        tb = B["total"] + EXT_FEE * len(B["ext"]) / n
        res[n] = (A, B, ta, tb)
        out.append("| %d placas | %.2f US$ | %d · %.2f US$ | **%.2f US$** | %.2f US$ | %d · %.2f US$ | **%.2f US$** | **%.0f %%** |"
                   % (n, A["total"], len(A["ext"]), EXT_FEE * len(A["ext"]) / n, ta, B["total"], len(B["ext"]),
                      EXT_FEE * len(B["ext"]) / n, tb, 100 * (1 - tb / ta)))
    A, B, _, _ = res[10]
    out.append("")
    c6 = ST["parts"].get("C7558096", {})
    out.append("REV A no se puede montar hoy: **ESP32-C6-MINI-1U-N4 sin existencias** en JLCPCB (%s uds.; el precio de "
               "%.4f US$ que devuelve sin existencias no es real, así que el coste de REV A está **subestimado** y la "
               "reducción real es mayor). BNO085: %s uds." % (c6.get("stock"), (c6.get("prices") or [[0, 0]])[0][1],
                                                              ST["parts"].get("C5189642", {}).get("stock")))
    for name, X in (("REV A", A), ("REV B", B)):
        out.append("")
        out.append("## %s — piezas por coste (10 placas)" % name)
        out.append("| LCSC | Pieza | Cant./placa | Precio unit. | Tipo | Existencias |")
        out.append("|---|---|---|---|---|---|")
        for code, mpn, k, pr, lib, stk in sorted(X["lines"], key=lambda r: -r[2] * r[3]):
            out.append("| %s | %s | %d | %.4f | %s | %s |" % (code, mpn, k, pr, "Basic" if lib == "base" else "Extended", stk))
        if X["missing"]:
            out.append("")
            out.append("Sin precio en la consulta: " + ", ".join(X["missing"]))
        if X["nostock"]:
            out.append("")
            out.append("**Sin existencias suficientes:** " + ", ".join(X["nostock"]))
    open(os.path.join(HERE, "..", "out_stock", "COSTE.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out[:12]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
