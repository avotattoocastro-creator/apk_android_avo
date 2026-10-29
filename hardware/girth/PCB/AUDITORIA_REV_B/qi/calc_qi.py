#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Auditoría Qi + cargador — AVO GIRTH REV B.  Cálculos reproducibles de AUDITORIA_QI.md.

Uso:  python3 calc_qi.py > calc_qi_salida.txt

Cada constante lleva la fuente de la que se tomó:
  [TI-RX]  TI BQ51013B datasheet, SLUSB62D (rev. D, sep-2020)  https://www.ti.com/lit/ds/symlink/bq51013b.pdf
  [TI-CHG] TI BQ2407x datasheet, SLUS810N (oct-2021)            https://www.ti.com/lit/ds/symlink/bq24074.pdf
  [TI-E2E] TI E2E "[FAQ] Schematic Checklist for Wireless Power RX"
           https://e2e.ti.com/support/power-management-group/power-management/f/power-management-forum/925464/faq-schematic-checklist-for-wireless-power-rx
  [MUR]    Murata NCP15XH103F03RC (hoja de producto)            https://static.chipdip.ru/lib/012/DOC013012218.pdf
  [TDK]    TDK WR202010-18M8-ID (ficha de producto)
           https://product.tdk.com/en/search/wireless-charge/wireless-charge/rx-coil-module/info?part_no=WR202010-18M8-ID
           https://product.tdk.com/en/search/wireless-charge/wireless-charge/rx-coil-module/catalog
           https://my.element14.com/tdk/wr202010-18m8-id/charging-coil-11uh-5-20mm-dia/dp/2790526
  [DIS]    Diseño: hardware/girth/PCB/fuente/avo_girth_pcb.py
  [EST]    Estimación del diseñador (DOCS/ANALISIS_ELECTRICO.md), NO medida.
  [SUP]    Supuesto de esta auditoría (declarado como tal).
"""
import math
import numpy as np

TWO_PI = 2 * math.pi
K0 = 273.15


def hdr(t):
    print("\n" + "=" * 100 + "\n" + t + "\n" + "=" * 100)


def nF(x):
    return x * 1e9


def fres(L, C):
    return 1.0 / (TWO_PI * math.sqrt(L * C))


# ------------------------------------------------------------------------------------------------ entradas
# BQ51013B [TI-RX]
FS_NOM, FS_MIN, FS_MAX = 100e3, 90e3, 105e3          # fS = 100 kHz +5/-10 %  (§9.2.1.2.2)
FD_NOM, FD_MIN, FD_MAX = 1e6, 0.9e6, 1.1e6           # fD = 1 MHz ±10 %
Q_MIN = 77                                           # Ec. 7: Q = 2π·fD·Ls/R > 77
KIMAX = 262.0                                        # A·Ω  IMAX = KIMAX/RILIM
KILIM = (303.0, 314.0, 321.0)                        # A·Ω  min/typ/max, ILIM (límite duro) = KILIM/RILIM
RILIM_SHORT = 120.0                                  # Ω   RILIM < 120 Ω = cortocircuito (latch)
VRECT_TABLE = [(0.0, 0.10, 7.08), (0.10, 0.20, 6.28), (0.20, 0.40, 5.53), (0.40, 9.9, 5.11)]  # Tabla 8-1
VOUT_TYP = 5.00
RTS = (18e3, 20e3, 22e3)                             # pull-up interno TS a VTSB (min/typ/max)
VCOLD_PCT = (0.565, 0.587, 0.608)                    # VCOLD (% VTSB) min/typ/max
VHOT_PCT = (0.185, 0.196, 0.207)                     # VHOT  (% VTSB) min/typ/max
TI_EX = dict(R1=4.23e3, R3=66.8e3, R0=10e3, beta=3380.0, Tc=-10.0, Th=100.0)  # ejemplo §8.3.13
TI_COIL_EX = dict(Ls=11e-6, Lsp=16e-6, Rdc=0.191, C1=158.3e-9, C2=2.3e-9)       # ejemplo §9.2.1.2.2
TI_COIL_TABLE = {  # Tabla 9-1 (Ls, Ls')  — para la relación Ls'/Ls de bobinas reales con atractor/escudo
    "Dexerials NSTC4832T7346-16B": (10.9e-6, 15.6e-6),
    "Mingstar 312-00015": (36.3e-6, 43.7e-6),
    "NuCurrent NC-01-R37L02O-25250R53 (Ø25)": (10.9e-6, 14.1e-6),
    "TDK WR483265-15F5-G": (13.2e-6, 18.8e-6),
    "Vishay IWAS-4832FF-50": (10.9e-6, 15.8e-6),
}
RJA_U1 = 37.7                                        # °C/W RHL (JEDEC)

# BQ2407x [TI-CHG]
KISET = (797.0, 890.0, 975.0)                        # A·Ω
KPRECHG = (70.0, 88.0, 106.0)                        # A·Ω
KILIM_CHG_LOW = (1330.0, 1525.0, 1720.0)             # A·Ω para ILIM 200–500 mA
ITERM_PCT = (0.09, 0.10, 0.11)                       # terminación (EN2=1/EN1=0 o USB500)
IIN_USB500 = (0.450, 0.475, 0.500)                   # A
VLOWV = 3.0                                          # V precarga→rápida (2.9/3.0/3.1)
VOREG_OFS = 0.225                                    # VO(REG) = VBAT + 225 mV (VBAT ≥ 3.2 V)
VOREG_LOW = 3.4                                      # VO(REG) = 3.4 V si VBAT < 3.2 V
ITS = (72e-6, 75e-6, 78e-6)
VHOT_CHG = (0.27, 0.30, 0.33)                        # V
VCOLD_CHG = (2.0, 2.1, 2.2)                          # V
RJA_U2 = 44.5                                        # °C/W RGT16 (JEDEC)
TJ_REG = 125.0
T_PRE, T_FAST = 1800.0, 18000.0                      # s, TMR abierto (típico)

# NTC Murata NCP15XH103F03RC [MUR]
NTC_R25, NTC_R_TOL = 10e3, 0.01
NTC_B, NTC_B_TOL = 3380.0, 0.01                      # B25/50
NTC_B2580 = 3428.0                                   # referencia

# Diseño [DIS]
C1_DES = 100e-9 + 100e-9 + 47e-9
C2_DES = 2.2e-9
C5_DNP = 1.0e-9
C_COMM = 22e-9
R1_ILIM, R_FOD, R_OS = 330.0, 200.0, 20e3
RISET, RILIM_CHG = 3.3e3, 3.3e3
RES_TOL = 0.01                                       # [SUP] resistencias 1 %
LS_DESIGNER = 10e-6                                  # supuesto del diseñador (AJUSTE_QI.md)
CELL_mAh = 500.0
I_SYS = (0.025, 0.045)                               # [EST] consumo del sistema
I_COIL_RMS = 0.6                                     # [EST] ANALISIS_ELECTRICO.md §1
VIN = 5.0

# Bobina seleccionada [TDK]
TDK_LS = 11e-6                                       # 11 µH @100 kHz, ±5 %
TDK_LS_TOL = 0.05
TDK_RDC_MAX = 0.40                                   # Ω (catálogo TDK 0,40; Mouser/LCSC 0,35)


def ntc_R(Tc, R25=NTC_R25, B=NTC_B):
    return R25 * math.exp(B * (1.0 / (Tc + K0) - 1.0 / (25.0 + K0)))


def ntc_T(R, R25=NTC_R25, B=NTC_B):
    return 1.0 / (1.0 / (25.0 + K0) + math.log(R / R25) / B) - K0


def par(a, b):
    return a * b / (a + b)


# ================================================================================================ 1. resonancia
hdr("1. RESONANCIA SERIE / PARALELO  (TI-RX Ec. 6: C1 = 1/((2π·fS)²·Ls'),  C2 = 1/((2π·fD)²·Ls − 1/C1))")


def C1_req(Lsp, f=FS_NOM):
    return 1.0 / ((TWO_PI * f) ** 2 * Lsp)


def C2_req(Ls, C1, f=FD_NOM):
    d = (TWO_PI * f) ** 2 * Ls - 1.0 / C1
    return float("inf") if d <= 0 else 1.0 / d


def fD_of(Ls, C1, C2):
    return 1.0 / (TWO_PI * math.sqrt(Ls * par(C1, C2)))


ex = TI_COIL_EX
print(f"Comprobación con el ejemplo de TI (Ls=11 µH, Ls'=16 µH): C1 = {nF(C1_req(ex['Lsp'])):.1f} nF (TI: 158.3), "
      f"C2 = {nF(C2_req(ex['Ls'], ex['C1'])):.2f} nF (TI: 2.3)")
print(f"Q ejemplo TI = 2π·1MHz·11µH/0.191Ω = {TWO_PI*1e6*ex['Ls']/ex['Rdc']:.0f} (> {Q_MIN})")

print(f"\nDiseño: C1 = {nF(C1_DES):.0f} nF, C2 = {nF(C2_DES):.1f} nF (+{nF(C5_DNP):.1f} nF C5 sin montar)")
print(f"Supuesto del diseñador Ls' = 10 µH -> C1 requerido = {nF(C1_req(LS_DESIGNER)):.1f} nF; "
      f"fS con 247 nF = {fres(LS_DESIGNER, C1_DES)/1e3:.1f} kHz")
lsp_lo = 1.0 / ((TWO_PI * FS_MAX) ** 2 * C1_DES)
lsp_hi = 1.0 / ((TWO_PI * FS_MIN) ** 2 * C1_DES)
print(f"Con C1 = 247 nF, fS queda en 90–105 kHz solo si Ls' está entre {lsp_lo*1e6:.2f} y {lsp_hi*1e6:.2f} µH")
for Ls in (8e-6, 10e-6, 12e-6):
    c2 = C2_req(Ls, C1_DES)
    print(f"  si Ls = {Ls*1e6:.0f} µH y C1 = 247 nF: C2 requerido = {nF(c2):.2f} nF; "
          f"fD con 2.2 nF = {fD_of(Ls, C1_DES, C2_DES)/1e6:.3f} MHz; con 3.2 nF (C5) = {fD_of(Ls, C1_DES, 3.2e-9)/1e6:.3f} MHz")

print("\nFórmula de C2 escrita en DOCS/AJUSTE_QI.md: C2 = 1/((2π·1MHz)²·(Ls − 1/((2π·100kHz)²·C1)))")
for Ls, Lsp in ((10e-6, 10e-6), (11e-6, 16e-6)):
    c1 = C1_req(Lsp)
    term = Ls - 1.0 / ((TWO_PI * FS_NOM) ** 2 * c1)          # = Ls − Ls'
    val = "división por cero / negativo" if term <= 0 else f"{nF(1/((TWO_PI*FD_NOM)**2*term)):.2f} nF"
    print(f"  Ls={Ls*1e6:.0f} µH, Ls'={Lsp*1e6:.0f} µH: Ls − 1/(ωS²C1) = Ls − Ls' = {term*1e6:+.2f} µH -> {val}  "
          f"(TI: {nF(C2_req(Ls, c1)):.2f} nF)")

# ------------------------------------------------------------------------- bobina seleccionada TDK WR202010-18M8-ID
hdr("2. BOBINA SELECCIONADA: TDK WR202010-18M8-ID (Ø20 mm, 11 µH ±5 % @100 kHz, Rdc ≤ 0,40 Ω)")
print(f"Q (Ec. 7 de TI, con Rdc máx.) = 2π·1MHz·11µH/{TDK_RDC_MAX} Ω = {TWO_PI*1e6*TDK_LS/TDK_RDC_MAX:.0f} (> {Q_MIN})")
print("TDK no publica Ls' (con transmisor). Relaciones Ls'/Ls de la Tabla 9-1 de TI (otras bobinas):")
ratios = []
for k, (a, b) in TI_COIL_TABLE.items():
    ratios.append(b / a)
    print(f"  {k:42s} Ls'/Ls = {b/a:.3f}")
print(f"  rango {min(ratios):.2f} … {max(ratios):.2f} (SUPUESTO para la TDK; hay que medir)")
cases = [("Ls' = Ls (cota)", 1.00), ("Ls'/Ls = 1.20", 1.20), ("Ls'/Ls = 1.29 (NuCurrent Ø25)", 14.1 / 10.9),
         ("Ls'/Ls = 1.45", 1.45)]
print(f"\n{'caso':32s} {'Ls_µH':>6s} {'Ls_µH´':>7s} {'C1req_nF':>9s} {'fS(247n)_kHz':>13s} {'C2req_nF':>9s}")
for name, r in cases:
    Lsp = TDK_LS * r
    c1 = C1_req(Lsp)
    print(f"{name:32s} {TDK_LS*1e6:6.1f} {Lsp*1e6:7.2f} {nF(c1):9.1f} {fres(Lsp, C1_DES)/1e3:13.1f} "
          f"{nF(C2_req(TDK_LS, c1)):9.2f}")

print("\nCombinaciones propuestas (C0G, 3 huellas 1206 en paralelo para C1; C4 + C5 para C2):")
proposals = [
    ("A  Ls'≈Ls (sin ferrita/atractor)", [100e-9, 100e-9, 33e-9], [2.2e-9, 0.33e-9], 1.00),
    ("B  Ls'/Ls≈1.29 (valor central)", [100e-9, 47e-9, 33e-9], [2.2e-9, 0.1e-9], 14.1 / 10.9),
    ("C  Ls'/Ls≈1.45", [100e-9, 47e-9, 15e-9], [2.2e-9, 0.1e-9], 1.45),
]
for name, c1s, c2s, r in proposals:
    c1, c2 = sum(c1s), sum(c2s)
    Lsp = TDK_LS * r
    fs = fres(Lsp, c1)
    fd = fD_of(TDK_LS, c1, c2)
    # sensibilidad: Ls ±5 % (TDK) y C0G ±5 % [SUP: tolerancia J]
    fs_lo = fres(Lsp * 1.05, c1 * 1.05); fs_hi = fres(Lsp * 0.95, c1 * 0.95)
    fd_lo = fD_of(TDK_LS * 1.05, c1 * 1.05, c2 * 1.05); fd_hi = fD_of(TDK_LS * 0.95, c1 * 0.95, c2 * 0.95)
    ok_s = FS_MIN <= fs_lo and fs_hi <= FS_MAX
    ok_d = FD_MIN <= fd_lo and fd_hi <= FD_MAX
    print(f"  {name}: C1 = {'+'.join(f'{nF(x):g}' for x in c1s)} = {nF(c1):.0f} nF -> fS = {fs/1e3:.1f} kHz "
          f"[{fs_lo/1e3:.1f}…{fs_hi/1e3:.1f}] {'OK' if ok_s else 'FUERA'};  C2 = {'+'.join(f'{nF(x):g}' for x in c2s)}"
          f" = {nF(c2):.2f} nF -> fD = {fd/1e6:.3f} MHz [{fd_lo/1e6:.3f}…{fd_hi/1e6:.3f}] {'OK' if ok_d else 'FUERA'}")
print("  (Con el C1 actual de 247 nF y la TDK, fS = "
      f"{fres(TDK_LS, C1_DES)/1e3:.1f} kHz si Ls'=Ls y {fres(TDK_LS*14.1/10.9, C1_DES)/1e3:.1f} kHz si Ls'/Ls=1.29)")

# Tensión sobre C1 con la corriente estimada de bobina
for c1 in (C1_DES, 180e-9, 162e-9):
    v = I_COIL_RMS / (TWO_PI * FS_NOM * c1)
    print(f"Tensión eficaz en C1 = {nF(c1):.0f} nF con {I_COIL_RMS} A rms [EST] a 100 kHz: {v:.2f} V rms "
          f"({v*math.sqrt(2):.2f} V pico) — C0G 50 V")
print(f"COMM: TI E2E FAQ recomienda ≈20 % de C1: con 247 nF -> {0.2*nF(C1_DES):.0f} nF; con 180 nF -> {0.2*180:.0f} nF; "
      f"diseño {nF(C_COMM):.0f} nF = {C_COMM/C1_DES*100:.1f} % de C1 (hoja de datos: 22 nF, 47 nF si falla la comunicación)")

# ================================================================================================ 3. ILIM Qi
hdr("3. BQ51013B: R_ILIM, IMAX, ILIM (TI-RX §8.3.4)")
RILIM = R1_ILIM + R_FOD
print(f"RILIM = R1 + RFOD = {R1_ILIM:.0f} + {R_FOD:.0f} = {RILIM:.0f} Ω (> {RILIM_SHORT:.0f} Ω: no es cortocircuito)")
IMAX = KIMAX / RILIM
print(f"IMAX = {KIMAX}/{RILIM:.0f} = {IMAX*1e3:.0f} mA")
r_lo, r_hi = RILIM * (1 - RES_TOL), RILIM * (1 + RES_TOL)
print(f"ILIM (límite duro) = KILIM/RILIM = {KILIM[1]/RILIM*1e3:.0f} mA típ.; rango con KILIM {KILIM[0]:.0f}…{KILIM[2]:.0f} "
      f"y resistencias ±1 %: {KILIM[0]/r_hi*1e3:.0f} … {KILIM[2]/r_lo*1e3:.0f} mA;  ILIM/IMAX = {KILIM[1]/KIMAX:.2f}")
print("Tabla 8-1 (VRECT objetivo) con IMAX =", f"{IMAX*1e3:.0f} mA:")
for a, b, v in VRECT_TABLE:
    lo, hi = a * IMAX, min(b, 1.2) * IMAX
    p_lo = (v - VOUT_TYP) * lo
    p_hi = (v - VOUT_TYP) * hi
    print(f"  {a*100:3.0f}–{min(b,1.2)*100:3.0f} % IMAX ({lo*1e3:4.0f}–{hi*1e3:4.0f} mA): VRECT = {v:.2f} V; "
          f"pérdida del regulador (VRECT−VOUT)·IOUT = {p_lo:.3f}–{p_hi:.3f} W")
p_reg_max = max((v - VOUT_TYP) * min(b, 1.2) * IMAX for a, b, v in VRECT_TABLE)
print(f"  máx. pérdida del regulador lineal ≈ {p_reg_max:.2f} W -> ΔTJ ≈ {p_reg_max*RJA_U1:.0f} °C (RθJA {RJA_U1} °C/W, "
      "sin contar el rectificador, cuyo RDS(on) no publica TI)")

# ================================================================================================ 4. TS del Qi
hdr("4. BQ51013B TS/CTRL con NTC NCP15XH103F03RC directo a GND (pull-up interno RTS a VTSB)")
# Topología (TI-RX §8.3.13, verificada reproduciendo el ejemplo): VTSB—RTS(20k)—TS—[(R1 + NTC) ∥ R3]—GND


def ts_ratio(Rntc, R1=0.0, R3=None, Rts=RTS[1]):
    Rb = Rntc + R1
    if R3 is not None:
        Rb = par(Rb, R3)
    return Rb / (Rb + Rts)


e = TI_EX
rc = ts_ratio(ntc_R(e["Tc"], e["R0"], e["beta"]), e["R1"], e["R3"])
rh = ts_ratio(ntc_R(e["Th"], e["R0"], e["beta"]), e["R1"], e["R3"])
print(f"Reproducción del ejemplo de TI (R1 4.23k, R3 66.8k, β 3380): ratio(−10 °C) = {rc*100:.1f} % (TI 58.7 %), "
      f"ratio(100 °C) = {rh*100:.1f} % (TI 19.6 %)  -> topología confirmada")


def thr_temp(pct, Rts, R25=NTC_R25, B=NTC_B, R1=0.0, R3=None):
    # resuelve ratio(T) = pct por bisección
    lo, hi = -60.0, 300.0
    f = lambda T: ts_ratio(ntc_R(T, R25, B), R1, R3, Rts) - pct
    for _ in range(200):
        m = 0.5 * (lo + hi)
        if f(lo) * f(m) <= 0:
            hi = m
        else:
            lo = m
    return 0.5 * (lo + hi)


def window(R1=0.0, R3=None, label=""):
    tc = thr_temp(VCOLD_PCT[1], RTS[1], R1=R1, R3=R3)
    th = thr_temp(VHOT_PCT[1], RTS[1], R1=R1, R3=R3)
    tcs, ths = [], []
    for rts in RTS:
        for pc in VCOLD_PCT:
            for r25 in (NTC_R25 * (1 - NTC_R_TOL), NTC_R25 * (1 + NTC_R_TOL)):
                for b in (NTC_B * (1 - NTC_B_TOL), NTC_B * (1 + NTC_B_TOL)):
                    tcs.append(thr_temp(pc, rts, r25, b, R1, R3))
        for ph in VHOT_PCT:
            for r25 in (NTC_R25 * (1 - NTC_R_TOL), NTC_R25 * (1 + NTC_R_TOL)):
                for b in (NTC_B * (1 - NTC_B_TOL), NTC_B * (1 + NTC_B_TOL)):
                    ths.append(thr_temp(ph, rts, r25, b, R1, R3))
    fmt = lambda t: f"{t:.1f}" if t < 200 else "> 200 (inalcanzable)"
    print(f"{label}: frío (EPT 0x00) por debajo de {tc:.1f} °C [{min(tcs):.1f} … {max(tcs):.1f}];  "
          f"caliente (EPT 0x03) por encima de {fmt(th)} °C [{fmt(min(ths))} … {fmt(max(ths))}]")
    return tc, th


R_cold = RTS[1] * VCOLD_PCT[1] / (1 - VCOLD_PCT[1])
R_hot = RTS[1] * VHOT_PCT[1] / (1 - VHOT_PCT[1])
print(f"NTC directa: R_NTC en VCOLD = {R_cold/1e3:.2f} kΩ, en VHOT = {R_hot/1e3:.3f} kΩ")
window(label="Diseño actual (NTC sola)")
window(e["R1"], e["R3"], label="Red del ejemplo de TI (R1 4.23k serie + R3 66.8k paralelo)")
window(4.22e3, 66.5e3, label="Red TI con valores E96 (R1 4.22k + R3 66.5k)")


def solve_net(Tc, Th):
    Rc, Rh = ntc_R(Tc), ntc_R(Th)
    # (R1+Rc)∥R3 = R_cold, (R1+Rh)∥R3 = R_hot  -> bisección en R3
    def r1_from(R3, Rt):
        # (R1+Rntc)·R3/(R1+Rntc+R3) = Rt -> R1+Rntc = Rt·R3/(R3−Rt)
        return Rt * R3 / (R3 - Rt)
    lo, hi = R_cold * 1.0001, 1e8
    g = lambda R3: (r1_from(R3, R_cold) - Rc) - (r1_from(R3, R_hot) - Rh)
    for _ in range(300):
        m = math.sqrt(lo * hi)
        if g(lo) * g(m) <= 0:
            hi = m
        else:
            lo = m
    R3 = math.sqrt(lo * hi)
    return r1_from(R3, R_hot) - Rh, R3


r1, r3 = solve_net(-20.0, 60.0)
print(f"Red para ventana −20 °C / 60 °C (alternativa): R1 = {r1/1e3:.2f} kΩ, R3 = {r3/1e3:.1f} kΩ")
window(r1, r3, label="  comprobación")
print(f"Resistencia fija de 10 kΩ (sin NTC): ratio = {ts_ratio(10e3)*100:.1f} % (entre {VHOT_PCT[2]*100:.1f} y "
      f"{VCOLD_PCT[0]*100:.1f} % en el peor caso de RTS: {ts_ratio(10e3, Rts=22e3)*100:.1f}…{ts_ratio(10e3, Rts=18e3)*100:.1f} %)")

# ================================================================================================ 5. BQ24072
hdr("5. BQ24072: corrientes, temporizadores, TS, disipación (TI-CHG SLUS810N)")
iset_lo, iset_hi = RISET * (1 - RES_TOL), RISET * (1 + RES_TOL)
ichg = KISET[1] / RISET
print(f"ICHG = KISET/RISET = 890/3300 = {ichg*1e3:.1f} mA [{KISET[0]/iset_hi*1e3:.0f} … {KISET[2]/iset_lo*1e3:.0f}] "
      f"= {ichg*1e3/CELL_mAh:.2f} C ({KISET[2]/iset_lo*1e3/CELL_mAh:.2f} C máx.) con 500 mAh")
print(f"  alternativa RISET = 3,6 kΩ: ICHG = {KISET[1]/3.6e3*1e3:.0f} mA = {KISET[1]/3.6e3*1e3/CELL_mAh:.2f} C")
ipre = KPRECHG[1] / RISET
print(f"IPRECHG = KPRECHG/RISET = {ipre*1e3:.1f} mA [{KPRECHG[0]/iset_hi*1e3:.1f} … {KPRECHG[2]/iset_lo*1e3:.1f}]")
print(f"ITERM ≈ 10 % ICHG = {ITERM_PCT[1]*ichg*1e3:.1f} mA [{ITERM_PCT[0]*KISET[0]/iset_hi*1e3:.1f} … "
      f"{ITERM_PCT[2]*KISET[2]/iset_lo*1e3:.1f}]")
iin = KILIM_CHG_LOW[1] / RILIM_CHG
print(f"IIN (modo ILIM, EN2=1/EN1=0) = 1525/3300 = {iin*1e3:.0f} mA [{KILIM_CHG_LOW[0]/(RILIM_CHG*1.01)*1e3:.0f} … "
      f"{KILIM_CHG_LOW[2]/(RILIM_CHG*0.99)*1e3:.0f}] frente a IMAX Qi {IMAX*1e3:.0f} mA y ILIM Qi mín. "
      f"{KILIM[0]/r_hi*1e3:.0f} mA")
print(f"Alternativa USB500 (EN1=1/EN2=0): {IIN_USB500[0]*1e3:.0f}/{IIN_USB500[1]*1e3:.0f}/{IIN_USB500[2]*1e3:.0f} mA, "
      "con VIN-DPM 4,35/4,5/4,63 V activo")
print(f"Temporizadores con TMR abierto: precarga {T_PRE/60:.0f} min, carga rápida {T_FAST/3600:.0f} h")
print(f"  carga en precarga durante 30 min: {ipre*T_PRE/3.6:.1f} mAh (típ.), {KPRECHG[0]/iset_hi*T_PRE/3.6:.1f} mAh (mín.)")
print(f"  tramo CC ideal 0→100 %: {CELL_mAh/(ichg*1e3):.2f} h (cota superior del CC; CV no modelado)")

print("\nTS del BQ24072 con NCP15XH103F03RC directo (ITS a NTC):")
Rh_c = VHOT_CHG[1] / ITS[1]; Rc_c = VCOLD_CHG[1] / ITS[1]
print(f"  R en VHOT = 0.30/75µA = {Rh_c/1e3:.2f} kΩ ; R en VCOLD = 2.1/75µA = {Rc_c/1e3:.2f} kΩ")
th_n, tc_n = ntc_T(Rh_c), ntc_T(Rc_c)
ths, tcs = [], []
for i in ITS:
    for vh in VHOT_CHG:
        for r25 in (NTC_R25 * 0.99, NTC_R25 * 1.01):
            for b in (NTC_B * 0.99, NTC_B * 1.01):
                ths.append(ntc_T(vh / i, r25, b))
    for vc in VCOLD_CHG:
        for r25 in (NTC_R25 * 0.99, NTC_R25 * 1.01):
            for b in (NTC_B * 0.99, NTC_B * 1.01):
                tcs.append(ntc_T(vc / i, r25, b))
print(f"  ventana de carga (β25/50 = 3380): {tc_n:.1f} °C … {th_n:.1f} °C ; peor caso frío [{min(tcs):.1f} … {max(tcs):.1f}] "
      f"caliente [{min(ths):.1f} … {max(ths):.1f}]")
print(f"  (con B25/80 = 3428 de referencia: caliente = {ntc_T(Rh_c, B=NTC_B2580):.1f} °C)")

print("\nDisipación del BQ24072 (VIN = 5,0 V; VOUT según VO(REG); ICHG limitada por IIN − ISYS — DPPM):")
print(f"{'VBAT':>5s} {'ISYS':>5s} {'modo':>9s} {'VOUT':>6s} {'ICHG_mA':>8s} {'IIN_mA':>7s} {'P_in_W':>7s} {'P_bat_W':>8s} "
      f"{'P_tot_W':>8s} {'ΔTJ_°C':>7s}")
rows = []
for isys in I_SYS:
    for vbat in (2.5, 2.9, 3.0, 3.2, 3.5, 3.7, 4.0, 4.2):
        if vbat < VLOWV:
            mode, ic = "precarga", ipre
        else:
            mode, ic = "rápida", ichg
        vout = VOREG_LOW if vbat < 3.2 else vbat + VOREG_OFS
        ic = min(ic, iin - isys)
        iin_act = ic + isys
        p_in = (VIN - vout) * iin_act
        p_bat = (vout - vbat) * ic
        p = p_in + p_bat
        rows.append(p)
        print(f"{vbat:5.2f} {isys*1e3:5.0f} {mode:>9s} {vout:6.3f} {ic*1e3:8.1f} {iin_act*1e3:7.1f} {p_in:7.3f} "
              f"{p_bat:8.3f} {p:8.3f} {p*RJA_U2:7.1f}")
print(f"Máximo: {max(rows):.3f} W -> ΔTJ = {max(rows)*RJA_U2:.0f} °C con θJA JEDEC {RJA_U2} °C/W; "
      f"TJ(REG) {TJ_REG:.0f} °C se alcanzaría con Tamb ≈ {TJ_REG - max(rows)*RJA_U2:.0f} °C (placa JEDEC, no la real)")
p_qi_in = VOUT_TYP * iin
print(f"Potencia pedida al Qi en carga máxima: 5 V × {iin*1e3:.0f} mA = {p_qi_in:.2f} W "
      "(clase TDK WR202010: 1–3 W)")

# ================================================================================================ 6. distancias NTC
hdr("6. Posición de las NTC en la placa (coordenadas POS de avo_girth_pcb.py)")
P = {"U1": (-19.5, -3.0), "U2": (-9.9, -3.0), "RT1": (-16.0, -1.6), "RT2": (-13.2, -0.9), "J2": (-24.2, 6.3)}
for a, b in (("RT1", "U1"), ("RT2", "U2"), ("RT2", "U1"), ("RT1", "J2"), ("RT2", "J2")):
    d = np.hypot(P[a][0] - P[b][0], P[a][1] - P[b][1])
    print(f"  {a}–{b}: {d:.1f} mm")
print("  La celda no lleva NTC propia: ambas NTC miden la placa junto a U1/U2, no la batería.")
