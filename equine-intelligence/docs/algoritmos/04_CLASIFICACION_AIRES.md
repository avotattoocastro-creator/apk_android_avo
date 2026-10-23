# Algoritmo: clasificación de aires
**Versión:** 1.0.0-dev1 · **Código:** `src/imu/motion.cpp` (`classify_gait`), `ml/avo_ml.py`
**Objetivo:** PARADO / PASO / TROTE / GALOPE / TRANSICIÓN por segmentos.
**Método actual:** reglas transparentes sobre velocidad GNSS y frecuencia de ciclo, con histéresis y duración mínima; calidad de segmento = nivel que cubre ≥80 % de los puntos.
**ML:** infraestructura de etiquetado, dataset, entrenamiento (centroide más cercano, interpretable) y evaluación dejando un caballo fuera. **No se entrega ningún modelo entrenado**: no hay datos reales etiquetados. La demo usa datos SINTÉTICOS y sus números no son exactitud real.
**Limitaciones:** umbrales orientativos, no validados con caballos reales.
