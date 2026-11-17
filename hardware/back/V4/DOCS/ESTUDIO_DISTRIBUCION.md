# AVO BACK V4 · estudio de distribuciones físicas (A–D) y elección

> REV B (30/10/2026): la distribución elegida no cambia; desaparece la bobina Qi bajo la PCB (suelo macizo) y aparecen los
> 3 contactos del fondo (SYS y BAT en la cola, GND en el centro de la placa). La longitud sigue fijada por la antena Q39.

Punto de partida: carcasa **Rev E.5** (`AVO_V22H_REV_E4_1_COMPLETA` + `AVO_V22H_REV_E5_TAPA`, modelo FreeCAD del usuario):
cápsula **166,2 × 59,0 × 17,1 mm**, techo interior a Z 15,1. Cotas tomadas del B-Rep, no de fotos.

## Qué fija la longitud (lo mismo en todas las alternativas)
1. **Batería 654060**: 60 × 40 × 6,5 (60,4 con holgura). No cabe girada (59 de ancho exterior).
2. **URTK1.2**: 43,4 × 43,7; el adaptador SMA en L sale **18,6 mm** más allá de su canto +X (cotas del anuncio de Boobrie
   y de la foto del montaje, como en la Rev E) y su cuerpo baja hasta Z 6,6.
3. **Antena Q39 Ø44,3 sobre el techo plano**: para que apoye entera, el centro del extremo redondo (R29,5) tiene que
   quedar a ±3,9 mm del eje de la L. Por tanto, **por detrás del canto de la URTK1.2 hay siempre ≈ 47,7 mm de cápsula**
   (18,6 + 29,5 − 0,4). En la Rev E ese tramo está casi vacío.
4. **Grosor**: el techo (15,1) no se toca. La URTK1.2 se queda a Z 9,6, como en la Rev E, para no mover la L, la torre
   de la tapa ni la rosca libre de la antena (4,4 mm).

## Alternativas
| | Disposición | Largo de la cápsula | Grosor | Comentario |
|---|---|---|---|---|
| Rev E.5 (actual) | Heltec sobre la batería; URTK1.2 al lado; cola casi vacía | **166,2** | 17,1 | referencia |
| **A** — todo en horizontal | batería · PCB · URTK1.2 · cola, todo sobre el suelo | ≈ 192 (estimado) | 17,1 | más larga que la actual: descartada |
| **B** — PCB portadora bajo la URTK1.2 | batería · (PCB + URTK1.2 apiladas en Z 2,5–11,2) · cola | ≈ 157 (estimado) | 17,1 | −9 mm; la PCB cabe bajo la URTK1.2 entre los separadores, pero la cola de 47,7 mm sigue vacía |
| **C** — mixta (**elegida**) | **URTK1.2 encima de la batería** (donde estaba la Heltec, misma altura); **PCB en la cola**, debajo de la L y de la antena | **118,2 (modelado)** | **17,1** | la cola, obligatoria por la antena, pasa a alojar la electrónica |
| **D** — contorno a medida | PCB con muescas para separadores, tornillos y pivotes; bolsillo en la base | — | — | **se aplica dentro de C** (contorno exportado del CAD a KiCad) |

Las cifras de A y B son estimaciones con las mismas reglas de C (batería 60,4 + URTK 43,4 + 47,7 de cola + cuello y
holguras); solo C está modelada y comprobada en B-Rep.

## Por qué C no aumenta el grosor
- Batería en su cuna del suelo, Z 0,8–7,3 (la bobina Qi ya no va debajo: pasa a estar bajo la PCB).
- Bandeja impresa 0,8 mm sobre la batería (Z 7,6–8,4) y **1,2 mm** libres hasta la cara inferior de la URTK1.2 (Z 9,6).
- La URTK1.2, la L, la torre y la rosca de la antena quedan **a las mismas cotas Z que la Rev E**.
- PCB V4 en un bolsillo de la base a **Z 2,5–3,5**, con la bobina Qi (Z 0,7–2,3) debajo. Bajo la L quedan 2,3 mm para
  componentes; en el resto de la cola, hasta 10,9 mm.
- Techo, chaflán, labio, junta, soporte (4,5), tela (1,5) y contraplaca (2,6): sin cambios. **Grosor del conjunto sin
  antena: 28,2 mm** (Z −11,1 … 17,1), **igual que la Rev E.5**.

## Resultado (B-Rep, `CAD/salida/verificacion_v4.json`)
| Parámetro | Rev E.5 | V4 | Diferencia |
|---|---|---|---|
| Largo de la cápsula | 166,2 mm | **118,2 mm** | **−48,0 mm (−28,9 %)** |
| Ancho | 59,0 mm | 59,0 mm | 0 |
| Alto de la cápsula | 17,1 mm | 17,1 mm | **0** |
| Grosor del conjunto (cápsula + soporte + tela + contraplaca) | 28,2 mm | 28,2 mm | **0** |
| Planta | 94,1 cm² | 65,8 cm² | −30,1 % |
| Volumen exterior de la cápsula | 157,8 cm³ | 110,1 cm³ | −47,7 cm³ (−30,3 %) |
| Volumen interior | 128,2 cm³ | 88,7 cm³ | −30,8 % |
| Antena (punta) | 57,9 mm | 57,9 mm | 0 |

Comprobación geométrica: 0 interferencias no previstas entre las 7 piezas y 17 referencias de electrónica (batería,
bobina, URTK1.2 con J1/J2/J3, L, antena Q39, antena FPC, imanes, PCB con la envolvente de cada componente, Hall).
Las únicas intersecciones son las previstas (junta TPU comprimida por el labio y dentro de su ranura).
