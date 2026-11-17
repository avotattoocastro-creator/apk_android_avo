"""Vista explosionada de la V4 (mismo motor de render_revD.py, piezas desplazadas en Z)."""
import os, sys, numpy as np
H = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(H, "render_v4.py"), encoding="utf-8").read().rsplit('if __name__ == "__main__":', 1)[0])
OFF = {"AVO_BACK_V4_TAPA": 62, "_antena_GNSS_Q39": 72, "_antena_FPC_2G4": 55, "_urtk_pcb": 34, "_urtk_modulo_ZED": 34, "_urtk_J3_GH6_estimado": 34,
       "_urtk_J1_USBC_estimado": 34, "_urtk_J2_SMA": 34, "_L_tuerca_y_cuerpo_hex": 34, "_L_cuerpo": 34, "_L_rosca_hembra": 34,
       "AVO_BACK_V4_ANILLOS_SEPARADOR": 22, "AVO_BACK_V4_BANDEJA_URTK": 20, "_pcb_placa": 12, "_pcb_componentes": 12,
       "_bateria_654060": 6, "_contactos_M2": -8, "_juntas_contactos": 4, "_pines_pogo_soporte": -22, "AVO_BACK_V4_BASE": 0, "_imanes_capsula": 0, "AVO_BACK_V4_SOPORTE": -22,
       "_imanes_soporte": -22, "AVO_BACK_V4_CONTRAPLACA": -40}
_load = load
def load(k):
    v, f = _load(k); v = v.copy(); v[:, 2] += OFF.get(k, 0); return v, f
COL["AVO_BACK_V4_ANILLOS_SEPARADOR"] = (0.98, 0.55, 0.15)
keys = [k for k in OFF if k in have]
im = render(keys, -125, 22, (60, 0, 38), 92, W=1500, H_=1300)
lab(im, "AVO BACK V4 — vista explosionada", "de arriba abajo: antena Q39 · tapa · antena FPC · URTK1.2 + L · anillos · bandeja · PCB V4 · batería · bobina Qi · base · soporte · contraplaca").save(os.path.join(O, "02_explosionada.png"))
print("ok")
