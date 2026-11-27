#!/usr/bin/env bash
# Monta ipad/demo3d (recursos de la página «Demostración» del iPad) a partir de demo/avo-3d:
#   2d/  versión de Muybridge (dominio público), siempre;
#   3d/  caballo + jockey de Enozone, solo si hay clave AVO_ASSETS_3D_KEY (modelos cifrados en el repositorio);
#   three/  three.js 0.160.0 dentro de la app (sin conexión), descargado de npm en el CI.
# Uso (desde la raíz del repositorio): scripts/demo3d/preparar_demo3d.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/demo/avo-3d"; OUT="$ROOT/ipad/demo3d"
rm -rf "$OUT"; mkdir -p "$OUT/2d" "$OUT/3d"
cp "$SRC/web-muybridge/index.html" "$SRC/web-muybridge/galope.webp" "$SRC/web-muybridge/esfera.webp" "$OUT/2d/"

# three.js 0.160.0 (build + examples/jsm) desde npm
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
command -v npm >/dev/null 2>&1 || brew install node >/dev/null
( cd "$tmp" && npm pack three@0.160.0 --silent >/dev/null && tar -xzf three-0.160.0.tgz )
mkdir -p "$OUT/three/build" "$OUT/three/examples/jsm/loaders"
cp "$tmp/package/build/three.module.js" "$OUT/three/build/"
# solo lo que usa la página (FBXLoader y sus dependencias, OrbitControls, RoomEnvironment, RoundedBoxGeometry, fflate)
J="$tmp/package/examples/jsm"
cp "$J/loaders/FBXLoader.js" "$OUT/three/examples/jsm/loaders/"
mkdir -p "$OUT/three/examples/jsm/libs" && cp "$J/libs/fflate.module.js" "$OUT/three/examples/jsm/libs/"
for d in curves controls environments geometries; do cp -R "$J/$d" "$OUT/three/examples/jsm/"; done

# página 3D: importmap y módulos a la copia local de three
sed -e 's#https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js#../three/build/three.module.js#' \
    -e 's#https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/#../three/examples/jsm/#' \
    "$SRC/web-3d/index.html" > "$OUT/3d/index.html"
if grep -q "cdn.jsdelivr.net/npm/three" "$OUT/3d/index.html"; then echo "::error::quedan rutas de three.js a la CDN"; exit 1; fi

if [ -n "${AVO_ASSETS_3D_KEY:-}" ]; then
  "$SRC/modelos_cifrados/descifrar.sh"
  mkdir -p "$OUT/3d/modelos" "$OUT/3d/tex"
  cp "$SRC/web-3d/modelos/modelos.zip" "$OUT/3d/modelos/"
  cp "$SRC/web-3d/tex/"* "$OUT/3d/tex/"
  echo "Demo 3D: modelos de Enozone incluidos"
else
  echo "::warning::Sin AVO_ASSETS_3D_KEY: la página Demostración usará la versión 2D de Muybridge"
fi
du -sh "$OUT"/*
