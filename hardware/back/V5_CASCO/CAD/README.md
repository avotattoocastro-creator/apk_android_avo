# AVO BACK V5 CASCO · cápsula estanca y base del casco (CAD REV A, 14/11/2026)

Generador: `avo_casco_v5.py` (CadQuery 2.4, en el CI con `build-back-v5-cad.yml`). Salidas en `out/`: STEP y STL de cada pieza, conjunto STEP e `informe.json`. Cortes: `cortes_v5.png` (`render_cortes.py`).

**Estado:** en el CI, 1 sólido por pieza y 0 interferencias con la PCB, los componentes de la cara F, la batería, la antena, el pogo y los imanes. **No impreso ni probado.**

## Medidas
- **Cápsula: 56,4 × 56,4 × 24,1 mm.** Interior de 51,6 (PCB de 51 + 0,3 por lado) y pared de 2,4.
- **Apilado, de abajo arriba:**
  - suelo de 1,4;
  - batería **≤ 50 × 37 × 8,5 mm (E)**;
  - 0,4 de holgura;
  - componentes de la cara F (≤ 2,6);
  - PCB de 1,6, que es también la junta entre base y tapa (z 14,5);
  - antena de 25 × 25 × 8,1 (E);
  - 0,3 de holgura;
  - techo de 1,2.
- **Sobre el casco:** unos 27,6 mm en el centro, con la base incluida.

| Pieza | Material | Peso |
|---|---|---|
| Base | PETG | 14,7 g |
| Tapa | PETG | 11,0 g |
| Junta | TPU 85A | 0,2 g |
| Base del casco | PETG | 20,8 g |

## Cierre
- **4 × M2,5 × 16** de cabeza cilíndrica desde abajo, por los taladros de la PCB (±22, ±22). Llevan una junta tórica de 2,5 × 1 bajo la cabeza, en un avellanado de Ø5 × 2,6.
- **Insertos M2,5** de Ø3,5 × 4 en los postes de la tapa. La PCB queda pinzada entre las columnas de la base y los postes de la tapa.
- **Junta TPU** de 0,9 × 1,1 en una ranura de 1,0 × 0,8 en la cara superior de la pared (≈ 27 % de compresión).
- **Antena:** 4 topes en el techo, a 0,3 por encima, para que no se levante.

## Fondo
- **Pogo de 5 contactos (ESTIMADO** a partir del STEP del de 3, con paso de 2,3):
  - franja −Y, con la cara a ras del fondo;
  - reborde apoyado por dentro y copa para el epoxi.
  - **Hace falta el STEP del modelo real.**
- **Imanes de sujeción:** 4 × Ø6 × 2 N52 en (±15,5, −22,5) y (±15, 22,5). Van metidos desde dentro, con 0,3 de piel.
- **Chaflán inferior** de 1,2 a 45°: es el que encaja en la base del casco.

## Base del casco
- **Forma:** anillo de PETG de 9,5 mm de ancho con un alojamiento de paredes a 45°, de 1,2 de alto. Con un golpe lateral, la cápsula sube por el chaflán y se suelta.
- **Imanes:** 4 enfrentados a los de la cápsula, más un imán Ø8 × 3 bajo el sensor Hall, en (−21,5, 2,0), que enciende la placa.
- **Cara inferior cóncava** de R110 (parámetro `HB["helmet_r"]`), para pegarla a la carcasa con cinta VHB. Hay que ajustarla al casco real.

## Pendiente
- STEP del pogo de 5 contactos y medidas de la batería.
- Dónde va el LED: propuesta de un LED de emisión lateral en el canto de la PCB, con una ventana fina en la pared.
- Prueba impresa: encaje de la PCB, junta, tornillos, fuerza de los imanes y despegue a 45°.
- Inmersión.
