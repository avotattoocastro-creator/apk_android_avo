# Arte de la pantalla de inicio (HeroArt)

`AVO.Windows/Views/HeroArt.xaml` = foto de referencia **sin** el logo ni los textos (borrados con *inpainting*,
`Assets/avo_home_hero.jpg`) + logo, «AVO» y textos redibujados como **vectores** en las coordenadas de la foto (2004×1098):
nítidos a cualquier tamaño y escala de Windows.

- Cabeza de caballo: trazada desde la imagen original (`vec.py` máscara → `skel.py` esqueleto y grosor → `outline2.py`
  contornos con grosor variable, extremos afinados y remates redondos; escala de grosor 1,08, afinado 0,18).
- «AVO»: geometría construida a mano sobre las medidas del original (`avo2.py`; la «A» con el travesaño unido solo a la pierna
  izquierda, como en el original).
- Textos: contornos de los glifos de **Montserrat** (licencia SIL OFL 1.1, `Montserrat-OFL.txt`; repositorio
  JulietaUla/Montserrat) con el interletrado ajustado al ancho del original (`text.py`). No hace falta instalar la fuente.
