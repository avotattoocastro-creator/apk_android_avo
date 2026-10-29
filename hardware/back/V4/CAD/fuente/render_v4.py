# -*- coding: utf-8 -*-
"""Vistas de revisión AVO BACK V4 (motor z-buffer de render_revD.py)."""
import os, sys, numpy as np
H = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(H, "render_revD.py"), encoding="utf-8").read().split('if __name__ == "__main__":')[0])
T = os.path.join(H, "salida", "_tess"); O = os.path.join(H, "salida", "IMAGENES"); os.makedirs(O, exist_ok=True)
COL.clear()
COL.update({"AVO_BACK_V4_TAPA": (0.86, 0.87, 0.90), "AVO_BACK_V4_BASE": (0.20, 0.55, 0.85), "AVO_BACK_V4_BANDEJA_URTK": (0.98, 0.78, 0.15),
            "AVO_BACK_V4_JUNTA_TPU": (0.1, 0.1, 0.1), "AVO_BACK_V4_ANILLOS_SEPARADOR": (0.98, 0.55, 0.15), "AVO_BACK_V4_SOPORTE": (0.93, 0.07, 0.16), "AVO_BACK_V4_CONTRAPLACA": (0.35, 0.37, 0.42),
            "_bateria_654060": (0.92, 0.77, 0.23), "_qi_bobina": (0.72, 0.45, 0.20), "_reed": (0.62, 0.83, 0.90),
            "_urtk_pcb": (0.05, 0.10, 0.35), "_urtk_modulo_ZED": (0.82, 0.82, 0.84), "_urtk_J3_GH6_estimado": (0.95, 0.95, 0.95), "_urtk_J1_USBC_estimado": (0.8, 0.8, 0.82),
            "_urtk_J2_SMA": (0.88, 0.72, 0.30), "_L_tuerca_y_cuerpo_hex": (0.88, 0.72, 0.30), "_L_cuerpo": (0.88, 0.72, 0.30), "_L_rosca_hembra": (0.92, 0.78, 0.35),
            "_antena_GNSS_Q39": (0.13, 0.13, 0.15), "_antena_FPC_2G4": (0.85, 0.55, 0.15), "_imanes_capsula": (0.55, 0.56, 0.60), "_imanes_soporte": (0.55, 0.56, 0.60),
            "_pcb_placa": (0.08, 0.40, 0.18), "_pcb_componentes": (0.25, 0.25, 0.28)})
for k in os.listdir(T):
    if "_P1_" in k or "_P2_" in k: COL[k[:-4]] = (0.20, 0.55, 0.85) if "BASE" in k else (0.93, 0.07, 0.16) if "SOPORTE" in k else (0.98, 0.78, 0.15) if "BANDEJA" in k else (0.86, 0.87, 0.90)
have = {k[:-4] for k in os.listdir(T)}
ELEC = [k for k in COL if k.startswith("_") and k != "_imanes_soporte" and k in have]
NO_ANT = [k for k in ELEC if k != "_antena_GNSS_Q39"]
CAP = ["AVO_BACK_V4_TAPA", "AVO_BACK_V4_BASE"]
ALL = CAP + ["AVO_BACK_V4_SOPORTE", "AVO_BACK_V4_CONTRAPLACA", "_antena_GNSS_Q39"]
import json
D = json.load(open(os.path.join(H, "salida", "informe_modelo_v4.json")))["RE"]["DERIVADOS"]; LL = D["LARGO"]; CX = LL / 2
jobs = {
 "01_conjunto": (ALL, -125, 26, (CX, 0, 20), 55, None, "AVO BACK V4 — conjunto montado", "cápsula %.1f × 59,0 × 17,1 (Rev E.5: 166,2 × 59,0 × 17,1) · antena Q39 sobre la tapa · soporte + contraplaca" % LL),
 "03_lateral": (ALL, -90, 0, (CX, 0, 22), 45, None, "Vista lateral (desde −Y)", "mismo grosor que la Rev E.5: cápsula 17,1 · soporte 4,5 · tela 1,5 · contraplaca 2,6"),
 "04_base_electronica": (["AVO_BACK_V4_BASE", "AVO_BACK_V4_BANDEJA_URTK"] + NO_ANT, -130, 45, (CX, 0, 5), 50, None, "Base con toda la electrónica",
                         "URTK1.2 sobre la batería (bandeja amarilla) · PCB V4 en la cola · L con J2 · antena FPC 2,4 GHz en el cuello (techo)"),
 "05_base_bateria_pcb": (["AVO_BACK_V4_BASE", "_bateria_654060", "_qi_bobina", "_reed", "_imanes_capsula", "_pcb_placa"], -130, 50, (CX, 0, 4), 50, None,
                         "Base: batería, PCB en la cola, bobina Qi y reed debajo", "bandeja y URTK1.2 retiradas"),
 "06_base_sin_electronica": (["AVO_BACK_V4_BASE"], -130, 55, (CX, 0, 4), 50, None, "Base sin electrónica",
                             "cuna de la batería · bolsillo de la PCB (Z 4,5) con alojamientos de bobina y reed · separadores M3 de la URTK1.2 · 8 tornillos"),
 "07_cola_L": (["AVO_BACK_V4_BASE", "_pcb_placa", "_urtk_pcb", "_urtk_J2_SMA", "_L_tuerca_y_cuerpo_hex", "_L_cuerpo", "_L_rosca_hembra"], -140, 40, (88, 0, 8), 22,
               ((60, -40, -5), (125, 40, 40)), "Cola: J2 + L sobre la PCB", "banda bajo J2/L sin componentes · separadores +X de la URTK1.2 atraviesan la PCB"),
 "08_tapa_interior": (["AVO_BACK_V4_TAPA"], -120, -60, (CX, 0, 10), 50, None, "Tapa — interior",
                      "8 columnas de cierre (todas completas) · topes de la L + torre · pisadores sobre la URTK1.2 y la PCB"),
 "09_soporte": (["AVO_BACK_V4_SOPORTE", "_imanes_soporte"], -125, 50, (CX, 0, 0), 50, None, "Soporte", "6 imanes de sujeción + 3 del reed · gancho del extremo · 6 insertos M3"),
 "10_cuello": (["AVO_BACK_V4_BASE", "AVO_BACK_V4_BANDEJA_URTK", "_bateria_654060", "_urtk_pcb", "_urtk_modulo_ZED", "_urtk_J3_GH6_estimado", "_urtk_J1_USBC_estimado", "_antena_FPC_2G4"], -150, 38, (22, 0, 8), 20,
                ((-5, -40, -5), (45, 40, 40)), "Cuello: extremo −X de la URTK1.2 sobre la bandeja", "2 pivotes en los agujeros −X · J1/J3 (estimados) · antena FPC en el techo"),
 "11_tapa_superior": (CAP + ["_antena_GNSS_Q39"], -90, 62, (CX, 0, 10), 45, None, "Tapa — vista superior", "antena Q39 Ø44,3 apoyada en el techo plano, sobre el centro del extremo redondo"),
 "21_base_abajo": (["AVO_BACK_V4_BASE"], -120, -50, (CX, 0, 3), 50, None, "Base vista desde abajo", "8 alojamientos de cabeza M3 + junta tórica · ranuras del cierre al soporte"),
}
if __name__ == "__main__":
    which = sys.argv[1:] or ["all"]
    for k, (keys, az, el, c, half, clip, t1, t2) in jobs.items():
        if which != ["all"] and k not in which: continue
        keys = [x for x in keys if x in have]
        im = render(keys, az, el, c, half, clip=clip); lab(im, t1, t2).save(os.path.join(O, k + ".png")); print(k, flush=True)
