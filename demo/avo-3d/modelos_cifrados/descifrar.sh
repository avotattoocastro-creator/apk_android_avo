#!/usr/bin/env bash
# Descifra los modelos 3D de Enozone (licencia del usuario, uso solo en la app privada) y los deja en web-3d/.
# La clave NO está en el repositorio: va en la variable AVO_ASSETS_3D_KEY (en CI, el secreto del mismo nombre).
# Uso: AVO_ASSETS_3D_KEY='...' ./descifrar.sh
set -euo pipefail
: "${AVO_ASSETS_3D_KEY:?Falta AVO_ASSETS_3D_KEY}"
cd "$(dirname "$0")"
# en macOS, «openssl» es LibreSSL: se usa el OpenSSL 3 de Homebrew si está (mismo formato que al cifrar)
OPENSSL=openssl
if command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ]; then OPENSSL="$(brew --prefix openssl@3)/bin/openssl"; fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
"$OPENSSL" enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in enozone_3d.zip.enc -out "$tmp/m.zip" -pass env:AVO_ASSETS_3D_KEY
python3 - "$tmp/m.zip" <<'PY'
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1])
os.makedirs('../web-3d/tex', exist_ok=True); os.makedirs('../web-3d/modelos', exist_ok=True)
for n in z.namelist():
    if n.startswith('tex/'):
        open('../web-3d/' + n, 'wb').write(z.read(n))
with zipfile.ZipFile('../web-3d/modelos/modelos.zip', 'w', zipfile.ZIP_DEFLATED) as out:
    out.writestr('horse.fbx', z.read('fbx/horse.fbx')); out.writestr('jockey.fbx', z.read('fbx/jockey.fbx'))
print('Modelos descifrados en web-3d/modelos y web-3d/tex')
PY
