"""AVO GIRTH REV B — simulaciones ngspice del corte de batería (Q10/Q11) y de la alimentación (BQ24072 → RT9080).

El circuito NO se copia a mano: las piezas y sus redes se leen de fuente/avo_girth_pcb.py (la misma fuente que
genera el esquema y la placa). Solo se añaden los estímulos y los modelos externos (batería, ESP32-C3, 5 V).

Uso:  python3 sim_revb.py [salida]      (necesita ngspice en el PATH; el CI lo instala con apt)
Escribe en salida/: netlists *.cir, datos *.dat, gráficas *.png, resultados.json y RESULTADOS_SPICE.md.
"""
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "fuente"))
import avo_girth_pcb as D  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "resultados")
os.makedirs(OUT, exist_ok=True)
NGSPICE = shutil.which("ngspice")

# ---------------------------------------------------------------- datos de hojas de datos (fuente en cada línea)
AO3400A = dict(vth=(0.65, 1.05, 1.45), ron_2v5=(0.024, 0.048))     # AOS AO3400A: VGS(th) @250 µA; RDS(on) @2,5 V típ/máx
AO3401A = dict(vth=(0.5, 0.9, 1.3), ron_2v5=(0.060, 0.085))       # AOS AO3401A: |VGS(th)| @250 µA; RDS(on) @−2,5 V
N2N7002 = dict(vth=(1.0, 2.1, 2.5), ron=(2.0, 7.5), vgs_on=5.0)   # 2N7002: VGS(th) 1–2,5 V; RDS(on) ≤ 7,5 Ω @5 V
RT9080_RDO = (0.31 / 0.6, 0.53 / 0.6)                              # Richtek DS9080: caída 0,31/0,53 V @600 mA
BQ_RPATH = (0.05, 0.10)                                            # TI SLUS937C: VDO(BAT-OUT) 50/100 mV @1 A
ESP_TX_A, ESP_RX_A = 0.350, 0.082                                  # ESP32-C3-MINI-1: TX 802.11b 20,5 dBm 350 mA; RX 82 mA
ESP_BOD = 2.51                                                      # ESP-IDF v5.5, ESP32-C3: nivel 7 (por defecto) 2,51 V
ESP_VMIN = 3.0                                                      # hoja ESP32-C3-MINI-1: VDD33 mín 3,0 V
I_TH = 250e-6


def fit_mos(vth_spec, ron, vgs_on):
    """Nivel 1: K tal que RDS(on)=ron a vgs_on y VGS(th) (a 250 µA) = vth_spec → (VTO, K)."""
    vto = vth_spec * 0.8
    for _ in range(60):
        k = 1.0 / (ron * (vgs_on - vto))
        vto = vth_spec - math.sqrt(2 * I_TH / k)
    return vto, k


def val(v):
    """'2u2' → 2.2e-6, '10M' → 1e7, '220R' → 220."""
    v = v.split()[0]
    m = re.match(r"^(\d+)([pnumkMR]?)(\d*)$", v)
    if not m:
        raise ValueError(v)
    a, unit, b = m.groups()
    mult = dict(p=1e-12, n=1e-9, u=1e-6, m=1e-3, k=1e3, M=1e6, R=1.0, **{"": 1.0})[unit]
    return float(a + ("." + b if b else "")) * mult


def nn(n):
    n = {"GND": "0", "+3V3": "VDD3"}.get(n, n)
    return re.sub(r"[^A-Za-z0-9_]", "_", n)


LATCH = ["Q10", "Q11", "D10", "D11", "D12", "D13", "R40", "R41", "R42", "R43", "R44", "R45", "C40", "C41",
         "Q16", "R49", "R50", "R31", "C33", "R32", "R33", "C34", "C20", "C19", "C21", "C22", "C23", "C24"]
PARTS = {p["ref"]: p for p in D.PARTS}


def circuit(P):
    """Netlist del corte + alimentación desde la fuente de diseño, con los parámetros P (dict)."""
    L = []
    der = P["derate"]
    for ref in LATCH:
        p = PARTS[ref]
        n = {k: nn(v) for k, v in p["nets"].items()}
        v = p["value"]
        if ref.startswith("R"):
            L.append("R%s %s %s %g" % (ref, n["1"], n["2"], val(v) * P["rtol"].get(ref, 1.0)))
        elif ref.startswith("C"):
            c = val(v) * der.get(ref, 1.0)
            L.append("C%s %s %s %g" % (ref, n["1"], n["2"], c))
        elif v == "BAV70":
            L.append("X%sa %s %s BAV70" % (ref, n["1"], n["3"]))
            L.append("X%sb %s %s BAV70" % (ref, n["2"], n["3"]))
        elif v == "AO3400A":
            L.append("X%s %s %s %s NMOS_LVL1 PARAMS: VTO=%g KP=%g" % ((ref, n["3"], n["1"], n["2"]) + P["nmos"]))
        elif v == "AO3401A":
            vto, k = P["pmos"]
            L.append("X%s %s %s %s PMOS_LVL1 PARAMS: VTO=%g KP=%g" % (ref, n["3"], n["1"], n["2"], -vto, k))
        elif v == "2N7002":
            L.append("X%s %s %s %s NMOS_LVL1 PARAMS: VTO=%g KP=%g" % ((ref, n["3"], n["1"], n["2"]) + P["n7002"]))
        else:
            raise ValueError(ref)
    # batería (J2): Voc + resistencia interna (celda + protección)
    L.append("VCELL CELL 0 DC %g" % P["vbat"])
    L.append("RCELL CELL BAT_RAW %g" % P["rint"])
    # reed SW1–SW2 (entre REED_HI y BAT_RAW), mandado por REEDCTL (1 = cerrado)
    L.append("SREED BAT_RAW REED_HI REEDCTL 0 SWREED")
    L.append(".model SWREED SW(VT=0.5 VH=0.1 RON=0.1 ROFF=1e12)")
    L.append("VREED REEDCTL 0 PWL(%s)" % P["reed_pwl"])
    # 5 V de carga (Qi/USB) en VIN5 (con C18 y una resistencia de fuente)
    L.append("VVIN VIN5S 0 PWL(%s)" % P["vin_pwl"])
    L.append("RVIN VIN5S VIN5 0.5")
    L.append("CC18 VIN5 0 1u")
    # BQ24072 sin entrada: FET BAT→OUT; con 5 V, OUT lo da el cargador (se modela como 4,2 V vía 0,1 Ω y diodo)
    L.append("RPATH VBAT VSYS %g" % P["rpath"])
    L.append("BCHG 0 VSYS I = u(V(VIN5)-4.3) * max(0, (4.4 - V(VSYS)) / 0.1)")
    # RT9080
    L.append("XU3 VSYS VDD3 0 RT9080 PARAMS: RDO=%g VREG=3.3" % P["rdo"])
    # ESP32-C3: temporizador de arranque (V(TIM) = segundos con 3V3 > 2,8 V), PWR_HOLD y consumo
    L.append("CTIM TIM 0 1u")
    L.append("BTIM 0 TIM I = u(V(VDD3)-2.8)*(1-V(RST))*1e-6 - (u(2.8-V(VDD3)) + V(RST))*1e-3*V(TIM)")
    L.append("VRST RST 0 PWL(%s)" % P["rst_pwl"])
    L.append("VHCMD HCMD 0 PWL(%s)" % P["hold_pwl"])       # 1 = el firmware quiere PWR_HOLD alto
    L.append("BHOLD 0 PWR_HOLD I = u(V(VDD3)-2.0) * (1-V(RST)) * u(V(TIM)-%g) * "
             "( V(HCMD)*(V(VDD3)-V(PWR_HOLD)) + (1-V(HCMD))*(0-V(PWR_HOLD)) ) / 40" % P["tboot"])
    L.append("VTX TXG 0 PULSE(0 1 0 10u 10u %g %g)" % (P["tx_on"], P["tx_per"]))
    L.append("BLOAD VDD3 0 I = u(V(VDD3)-%g) * (1-V(RST)*0.7) * ( u(%g-V(TIM))*0.060 + "
             "u(V(TIM)-%g)*(V(SLP)*20e-6 + (1-V(SLP))*(%g + u(V(TIM)-%g-0.2)*V(TXG)*%g)) )"
             % (ESP_BOD, P["tboot"], P["tboot"], ESP_RX_A, P["tboot"], ESP_TX_A - ESP_RX_A))
    L.append("VSLP SLP 0 PWL(%s)" % P["sleep_pwl"])     # 1 = sueño profundo (tras APAGAR)
    return L


def base_params(**kw):
    P = dict(vbat=3.7, rint=0.2, rpath=BQ_RPATH[0], rdo=RT9080_RDO[0], tboot=0.5,
             nmos=fit_mos(AO3400A["vth"][1], AO3400A["ron_2v5"][0], 2.5),
             pmos=fit_mos(AO3401A["vth"][1], AO3401A["ron_2v5"][0], 2.5),
             n7002=fit_mos(N2N7002["vth"][1], N2N7002["ron"][0], N2N7002["vgs_on"]),
             derate=dict(C40=0.7, C41=0.85, C20=0.6, C19=0.6, C21=0.6, C22=0.7, C23=0.5),
             rtol={}, reed_pwl="0 0 0.1 0 0.101 1", vin_pwl="0 0", rst_pwl="0 0", hold_pwl="0 1",
             sleep_pwl="0 0", tx_on=2e-3, tx_per=10e-3, tstop=6.0, tstep=1e-3)
    P.update(kw)
    return P


def run(name, P, probes=("V(VDD3)", "V(PWR_G)", "V(VBAT)", "V(PWR_HOLD)", "V(REED)", "I(VCELL)"), op=False):
    cir = os.path.join(OUT, name + ".cir")
    dat = os.path.join(OUT, name + ".dat")
    L = ["* AVO GIRTH REV B · " + name, ".include %s" % os.path.join(HERE, "modelos.lib")] + circuit(P)
    if op:
        L += [".control", "op", "print all > %s" % dat, "quit", ".endc", ".end"]
    else:
        L += [".options method=gear reltol=1e-4 abstol=1e-12",
              ".control", "set wr_singlescale", "set wr_vecnames",
              "tran %g %g 0 %g" % (P["tstep"], P["tstop"], P["tstep"]),
              "wrdata %s %s" % (dat, " ".join(probes)), "quit", ".endc", ".end"]
    open(cir, "w").write("\n".join(L) + "\n")
    r = subprocess.run([NGSPICE, "-b", cir], capture_output=True, text=True, timeout=600)
    open(os.path.join(OUT, name + ".log"), "w").write(r.stdout + r.stderr)
    if op:
        return open(dat).read()
    import numpy as np
    d = np.loadtxt(dat, skiprows=1)
    cols = open(dat).readline().split()
    return {c: d[:, i] for i, c in enumerate(cols)}


def first_after(t, cond, t0):
    import numpy as np
    idx = np.where((t >= t0) & cond)[0]
    return float(t[idx[0]]) if len(idx) else None


def plot(name, res, title, marks=()):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    t = res["time"]
    fig, ax = plt.subplots(3, 1, figsize=(10, 7.5), sharex=True)
    ax[0].plot(t, res["v(vdd3)"], label="+3V3"); ax[0].plot(t, res["v(vbat)"], label="VBAT")
    ax[0].axhline(ESP_VMIN, ls="--", c="gray", lw=0.8); ax[0].axhline(ESP_BOD, ls=":", c="red", lw=0.8)
    ax[0].set_ylabel("V"); ax[0].legend(loc="upper right"); ax[0].grid(alpha=0.3)
    ax[1].plot(t, res["v(pwr_g)"], label="PWR_G"); ax[1].plot(t, res["v(pwr_hold)"], label="PWR_HOLD")
    ax[1].plot(t, res["v(reed)"], label="GPIO1 (REED)", alpha=0.7)
    ax[1].axhline(1.45, ls="--", c="gray", lw=0.8); ax[1].set_ylabel("V"); ax[1].legend(loc="upper right")
    ax[1].grid(alpha=0.3)
    ax[2].plot(t, -res["i(vcell)"] * 1e3); ax[2].set_ylabel("I celda (mA)"); ax[2].set_xlabel("t (s)")
    ax[2].grid(alpha=0.3)
    for m in marks:
        for a in ax:
            a.axvline(m, c="k", lw=0.5, alpha=0.4)
    fig.suptitle(title, fontsize=10)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, name + ".png"), dpi=110)
    plt.close(fig)


def main():
    import numpy as np
    if not NGSPICE:
        print("ngspice no está instalado: no se puede simular"); sys.exit(2)
    ver = subprocess.run([NGSPICE, "-v"], capture_output=True, text=True).stdout.strip().split("\n")[0]
    R = dict(ngspice=ver, escenarios={}, montecarlo={})

    # ---------- 1. Ventana sin PWR_HOLD (el ESP32 nunca lo pone): ¿cuánto tiempo hay 3V3 > 3,0 V?
    tab = []
    for vb in (3.0, 3.3, 3.5, 3.7, 4.2):
        for corner, (vth_n, der40, der41) in {"típico": (1.05, 0.7, 0.85),
                                              "peor": (1.45, 0.45, 0.6)}.items():
            P = base_params(vbat=vb, hold_pwl="0 0", tboot=99, tstop=8.0,
                            nmos=fit_mos(vth_n, AO3400A["ron_2v5"][1 if corner == "peor" else 0], 2.5))
            P["derate"].update(C40=der40, C41=der41)
            name = "ventana_%s_%.1fV" % ("tip" if corner == "típico" else "peor", vb)
            res = run(name, P)
            t = res["time"]; v3 = res["v(vdd3)"]
            on = first_after(t, v3 > ESP_VMIN, 0.1)
            off = first_after(t, v3 < ESP_VMIN, on + 0.01) if on else None
            w = (off if off else t[-1]) - on if on else 0.0
            tab.append(dict(vbat=vb, caso=corner, t_3v3_ok=on, ventana_s=round(w, 3), pwr_g_max=float(res["v(pwr_g)"].max())))
            if vb in (3.3, 4.2):
                plot(name, res, "Reed cerrado sin PWR_HOLD · celda %.1f V · caso %s" % (vb, corner), (0.1,))
    R["escenarios"]["ventana_sin_hold"] = tab

    # ---------- 2. Arranque normal con PWR_HOLD tras 0,5 s y ráfagas de TX (350 mA, 2 ms cada 10 ms)
    tab = []
    for vb, rint, rdo, rpath in ((4.2, 0.2, RT9080_RDO[0], BQ_RPATH[0]), (3.7, 0.2, RT9080_RDO[0], BQ_RPATH[0]),
                                 (3.5, 0.3, RT9080_RDO[1], BQ_RPATH[1]), (3.4, 0.3, RT9080_RDO[1], BQ_RPATH[1]),
                                 (3.3, 0.3, RT9080_RDO[1], BQ_RPATH[1]), (3.3, 0.2, RT9080_RDO[0], BQ_RPATH[0])):
        P = base_params(vbat=vb, rint=rint, rdo=rdo, rpath=rpath, tstop=3.0, tstep=50e-6)
        name = "arranque_%.1fV_rint%.1f_rdo%.2f" % (vb, rint, rdo)
        res = run(name, P)
        t = res["time"]; v3 = res["v(vdd3)"]
        win = (t > 1.0)
        tab.append(dict(vbat=vb, rint=rint, rdo=rdo, rpath=rpath, v3_min_tx=round(float(v3[win].min()), 3),
                        vbat_min=round(float(res["v(vbat)"][win].min()), 3),
                        sigue_encendida=bool(v3[-1] > 3.0), bajo_3v0=bool(v3[win].min() < ESP_VMIN),
                        brownout=bool(v3[win].min() < ESP_BOD)))
        if (vb, rint) in ((3.7, 0.2), (3.3, 0.3)):
            plot(name, res, "Arranque y TX · celda %.1f V, Rint %.1f Ω, Rdo %.2f Ω" % (vb, rint, rdo), (0.1,))
    R["escenarios"]["arranque_tx"] = tab

    # ---------- 3. Reinicio del ESP32 (PWR_HOLD en alta impedancia) de 0,3 / 0,6 / 1,0 / 1,5 s a t = 3 s
    tab = []
    for dur in (0.3, 0.6, 1.0, 1.5):
        for corner, vth in (("típico", 1.05), ("peor", 1.45)):
            P = base_params(vbat=3.5, tstop=7.0, rst_pwl="0 0 3 0 3.001 1 %g 1 %g 0" % (3 + dur, 3.001 + dur),
                            nmos=fit_mos(vth, AO3400A["ron_2v5"][0], 2.5), reed_pwl="0 0 0.1 0 0.101 1 1 1 1.001 0")
            if corner == "peor":
                P["derate"].update(C41=0.6)
            name = "reinicio_%.1fs_%s" % (dur, "tip" if corner == "típico" else "peor")
            res = run(name, P)
            t = res["time"]; v3 = res["v(vdd3)"]
            after = t > 3.0
            tab.append(dict(reinicio_s=dur, caso=corner, v3_min=round(float(v3[after].min()), 3),
                            sobrevive=bool(v3[after].min() > ESP_BOD and v3[-1] > 3.0)))
            if dur in (0.6, 1.5) and corner == "peor":
                plot(name, res, "Reinicio de %.1f s (reed ya abierto) · caso peor" % dur, (3.0, 3.0 + dur))
    R["escenarios"]["reinicio"] = tab

    # ---------- 4. Apagado (PWR_HOLD = 0 a t = 3 s) con el reed cerrado y con el reed abierto
    tab = []
    for reed_cerrado in (True, False):
        reed = "0 0 0.1 0 0.101 1" if reed_cerrado else "0 0 0.1 0 0.101 1 1 1 1.001 0"
        P = base_params(vbat=3.7, tstop=9.0, hold_pwl="0 1 3 1 3.001 0", sleep_pwl="0 0 3 0 3.001 1", reed_pwl=reed)
        name = "apagado_reed_%s" % ("cerrado" if reed_cerrado else "abierto")
        res = run(name, P)
        t = res["time"]; v3 = res["v(vdd3)"]
        toff = first_after(t, v3 < 1.0, 3.0)
        tab.append(dict(reed_cerrado=reed_cerrado, t_apagado_s=round(toff - 3.0, 3) if toff else None,
                        vuelve_a_encender=bool(v3[-1] > 1.0), i_celda_final_uA=round(float(-res["i(vcell)"][-1]) * 1e6, 3)))
        plot(name, res, "Apagado con PWR_HOLD = 0 · reed %s" % ("cerrado" if reed_cerrado else "abierto"), (3.0,))
    R["escenarios"]["apagado"] = tab

    # ---------- 5. Reencendido: reed abierto 1 s, apagado, y vuelto a cerrar Δ s después de quitar la energía
    tab = []
    for dt in (0.5, 1.0, 2.0, 3.0, 5.0):
        reed = "0 0 0.1 0 0.101 1 1 1 1.001 0 %g 0 %g 1" % (5 + dt, 5.001 + dt)
        P = base_params(vbat=3.5, tstop=9 + dt, hold_pwl="0 1 4 1 4.001 0", sleep_pwl="0 0 4 0 4.001 1 %g 1 %g 0"
                        % (5 + dt, 5.001 + dt), reed_pwl=reed)
        P["derate"].update(C40=0.45, C41=0.6)
        P["nmos"] = fit_mos(1.45, AO3400A["ron_2v5"][1], 2.5)
        name = "reencendido_%.1fs" % dt
        res = run(name, P)
        t = res["time"]; v3 = res["v(vdd3)"]
        re_on = first_after(t, v3 > ESP_VMIN, 5 + dt)
        tab.append(dict(reed_reabierto_tras_s=dt, reengancha=bool(re_on is not None)))
        if dt in (1.0, 3.0):
            plot(name, res, "Reed reabierto y vuelto a cerrar %.1f s después · caso peor" % dt, (1.0, 4.0, 5 + dt))
    R["escenarios"]["reencendido"] = tab

    # ---------- 6. Con 5 V de carga (Qi/USB): siempre encendida aunque PWR_HOLD = 0; al quitar los 5 V se apaga
    P = base_params(vbat=3.7, tstop=12.0, reed_pwl="0 0", vin_pwl="0 0 0.1 0 0.11 5 6 5 6.01 0",
                    hold_pwl="0 1 2 1 2.001 0", sleep_pwl="0 0 2 0 2.001 1")
    res = run("carga_5V", P)
    t = res["time"]; v3 = res["v(vdd3)"]
    R["escenarios"]["carga_5V"] = dict(encendida_con_5V_y_hold0=bool(v3[(t > 3) & (t < 5.9)].min() > 3.0),
                                       apagada_tras_quitar_5V=bool(v3[-1] < 1.0),
                                       t_apagado_tras_quitar_s=round((first_after(t, v3 < 1.0, 6.0) or 99) - 6.0, 3))
    plot("carga_5V", res, "Base Qi/USB (5 V de 0,1 a 6 s), PWR_HOLD = 0 desde 2 s, reed abierto", (0.1, 2.0, 6.0))

    # ---------- 7. Consumo apagado (punto de trabajo)
    for reed_c in (False, True):
        P = base_params(vbat=4.2, reed_pwl="0 %d" % (1 if reed_c else 0), hold_pwl="0 0", tboot=99)
        txt = run("apagada_reed_%s" % ("cerrado" if reed_c else "abierto"), P, op=True)
        m = re.search(r"vcell#branch\s*=\s*([-+0-9.eE]+)", txt)
        R["escenarios"]["consumo_apagada_reed_%s_uA" % ("cerrado" if reed_c else "abierto")] = \
            round(-float(m.group(1)) * 1e6, 4) if m else txt[:400]

    # ---------- 8. Monte Carlo de la ventana sin PWR_HOLD y del reinicio de 0,6 s (tolerancias)
    random.seed(20261029)
    mc_w, mc_r = [], []
    for k in range(int(os.environ.get("MC_N", "200"))):
        vth_n = random.uniform(*AO3400A["vth"][0::2]); vth_p = random.uniform(*AO3401A["vth"][0::2])
        d40 = random.uniform(0.45, 1.1); d41 = random.uniform(0.6, 1.1)
        rt = {r: random.uniform(0.99, 1.01) for r in ("R40", "R41", "R42", "R43", "R44", "R45")}
        vb = random.uniform(3.2, 4.2)
        P = base_params(vbat=vb, hold_pwl="0 0", tboot=99, tstop=6.0, tstep=2e-3,
                        nmos=fit_mos(vth_n, AO3400A["ron_2v5"][1], 2.5),
                        pmos=fit_mos(vth_p, AO3401A["ron_2v5"][1], 2.5), rtol=rt)
        P["derate"].update(C40=d40, C41=d41)
        res = run("mc_ventana_%03d" % k, P, probes=("V(VDD3)",))
        t = res["time"]; v3 = res["v(vdd3)"]
        on = first_after(t, v3 > ESP_VMIN, 0.1)
        off = first_after(t, v3 < ESP_VMIN, on + 0.01) if on else None
        mc_w.append(dict(vth_n=vth_n, vth_p=vth_p, d40=d40, d41=d41, vbat=vb,
                         ventana=((off if off else t[-1]) - on) if on else 0.0))
        P = base_params(vbat=vb, tstop=5.0, tstep=2e-3, rst_pwl="0 0 3 0 3.001 1 3.6 1 3.601 0",
                        nmos=fit_mos(vth_n, AO3400A["ron_2v5"][1], 2.5),
                        pmos=fit_mos(vth_p, AO3401A["ron_2v5"][1], 2.5), rtol=rt,
                        reed_pwl="0 0 0.1 0 0.101 1 1 1 1.001 0")
        P["derate"].update(C40=d40, C41=d41)
        res = run("mc_reinicio_%03d" % k, P, probes=("V(VDD3)",))
        t = res["time"]; v3 = res["v(vdd3)"]
        mc_r.append(dict(vth_n=vth_n, d41=d41, vbat=vb, v3_min=float(v3[t > 3.0].min())))
    for f in os.listdir(OUT):
        if f.startswith("mc_") and (f.endswith(".dat") or f.endswith(".log")):
            os.remove(os.path.join(OUT, f))          # se guardan los netlists de ejemplo y el resumen
    w = np.array([m["ventana"] for m in mc_w]); r = np.array([m["v3_min"] for m in mc_r])
    worst = min(mc_w, key=lambda m: m["ventana"])
    R["montecarlo"] = dict(n=len(mc_w), ventana_min_s=round(float(w.min()), 3), ventana_p1_s=round(float(np.percentile(w, 1)), 3),
                           ventana_mediana_s=round(float(np.median(w)), 3), peor_caso=worst,
                           reinicio_0_6s_v3_min=round(float(r.min()), 3),
                           reinicio_fallos=int((r < ESP_BOD).sum()))
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(1, 2, figsize=(11, 4))
    ax[0].scatter([m["vth_n"] for m in mc_w], w, c=[m["vbat"] for m in mc_w], s=12)
    ax[0].set_xlabel("VGS(th) Q11 (V)"); ax[0].set_ylabel("ventana sin PWR_HOLD (s)"); ax[0].grid(alpha=0.3)
    ax[0].axhline(0.5, c="red", ls="--", lw=0.8)
    ax[1].hist(r, bins=30); ax[1].axvline(ESP_BOD, c="red", ls="--"); ax[1].set_xlabel("3V3 mínimo en un reinicio de 0,6 s (V)")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "montecarlo.png"), dpi=110); plt.close(fig)

    json.dump(R, open(os.path.join(OUT, "resultados.json"), "w"), indent=1, ensure_ascii=False, default=float)
    print(json.dumps(R, indent=1, ensure_ascii=False, default=float))


if __name__ == "__main__":
    main()
