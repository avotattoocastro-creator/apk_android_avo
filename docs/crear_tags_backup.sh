#!/usr/bin/env bash
# AVO Performance Horse — etiquetas de respaldo de TODAS las ramas (estado auditado el 12/11/2026)
# Uso: dentro de un clon con permiso de escritura:  bash docs/crear_tags_backup.sh   (y luego: git push origin --tags)
# Cada etiqueta apunta al commit EXACTO auditado. Si una rama se ha movido desde entonces,
# el script lo avisa y etiqueta igualmente el commit auditado (no el nuevo), para no congelar algo no revisado.
set -euo pipefail
git fetch origin --prune
FECHA=2026-11-12
n=0; movidas=0
while read -r sha rama; do
  actual=$(git rev-parse -q --verify "origin/$rama" || echo "")
  if [ -z "$actual" ]; then echo "AVISO: la rama $rama ya no existe en origin (se etiqueta igual el commit auditado)";
  elif [ "$actual" != "$sha" ]; then echo "AVISO: $rama se ha movido: auditado ${sha:0:7}, ahora ${actual:0:7}"; movidas=$((movidas+1)); fi
  git tag -a "backup/$FECHA/$rama" "$sha" -m "Respaldo de $rama antes de integrar en develop ($FECHA)" 2>/dev/null \
    && n=$((n+1)) || echo "ya existe: backup/$FECHA/$rama"
done <<'LISTA'
2817c467d68f1d83624e6ac08ecbdc38e74983a8 audit/avo-girth-pcb-revb
b7724eeb29bc002c6a311bb7117ae3e3ad3f8eda ci/ipad-smoke
d6a44499ca13ec3bc8c084eec43b27d22bebfbfc ci/ipad-visual-evidence
902d6b46e8221394e2c6515c949fa83790ada7e4 ci/windows-visual-evidence
18a98231c3a234dc0cc7c003a724d1d691dc747a develop/avo-performance-horse
85e5295c4639d158a034a611c6b1ac44c4c680ae diag/back-3-13-8-pololu-libre
4e1f3a75bc562603e7fc53d6a8f02f503502e6e2 export/avo-girth-aisler
f25d18e07213cefb177e82ff56c6ea81fd135dd4 feature/android-2-8-wifi-ble
a5a3c540cc4c29d1bb998e2d1b1bfe31c03139e6 feature/android-v1-4-ota-pecho
3b05022bfabcf29bfa7516cd31b0e2eaa76bc146 feature/android-v1-9-nfc-segments
05fdfe61379e94cddfa70833196ab1c4c6563465 feature/avo-back-rev-e7-iman
b008cb5fe9719455dc9d12dfe64199a97321692f feature/avo-back-v4
c993be249c43f1a9ff0414f5353d61ecec921627 feature/avo-equine-intelligence-engine
24f27bb5e3353dde2098bfd801324124dc110e55 feature/avo-firebase-sync
a7e3d0f8bc58e7a6375b0d10481d1677ca224ee1 feature/avo-girth-pcb
6fe0f10589379fadbb795d8aabda498157346176 feature/avo-license-nfc
90c675b8a556da86d67bcb0a9c01ef24e69a8205 feature/avo-measurement-engine-v4
82d848bbf4d0f0c37b94b694ac326f5428969779 feature/avo-nfc-identity
5e874009dd06de51209521628031f3b41d78ab54 feature/avo-ntrip-auto
21f6eda9a645d10e7029fc207b585ae0e22d1af0 feature/avo-signer-android-v0.1
7c87f88a0b094e7e59e5c67fc6080b62a0ad1bf7 feature/avo-training-analytics
e4c3e662536bb869b0b89a967ca3f6aeb4c32214 feature/avo-usb-updater
66d22db42c32ea3e831b42b7a5eab70290970f27 feature/avo-wifi-sync
f727a4221f31b9c4c75461ec31c985e9978a9706 feature/chest-3-7-7-despertar-espalda
4c2d5ab102c077d86326c43f40d163cd3510ffd0 feature/chest-usb-pc-sync
494cf73a6dadb5e1ad2e1ac4c963443076d345e9 feature/chest-v3-7-6-gnss-quality
aebad7ca77bc70bff9173b5a8984eb9abb251d83 feature/girth-fw-0-4-0-bno085
c205dd9f8b4315ae06063d71cb5c1aac4c03524d feature/girth-rev5-10-pulso
8034e5d930c11cca3c7cda7bf46fbfa5e3499ca6 feature/girth-rev5-7-cama
7ab072aa0284af277bbbbaa7c93c4df0f1abdffe feature/girth-rev5-8-1-curvas
29d8a1c924d2f448dbcedfd295579f216786ffed feature/girth-rev5-8-cierres
bf56a2ac1d7edbb869e19122d8e611c1624f24e5 feature/girth-rev5-9-1-pogo-medido
cc0386a2910c46502b59ab444116d55be102d970 feature/girth-rev5-9-2-pogo-empotrado
e9361df9bd4888be2942732a304f22fbf8198de0 feature/girth-rev5-9-pogo
75e8ecd203dbd75131fddb34f1da03345f962dfe feature/ipad-analisis-entreno
d42c090b956bc326adbb4bd67013711c07a8397d feature/ipad-app
28bd3cde0cd4899920af455448d67d86940be502 feature/windows-advanced-analysis
f526de54e5a7afa238dd2bc01d350059845e8c1d feature/windows-girth-bno-units
810130465404ffc5f172a4aa600543e9c3e6aa2d feature/windows-girth-movimiento
079566d5bd5ea27e489d09200b1da1e8020fbb35 firmware/chest-v3.5.4-sd-fix
aa1545675f427b214754f8eb3bb8ce08e6b39429 firmware/chest-v3.5.5-ota-usb-fix
d184a223db7097f7f5fa827136d64afe45d562f7 firmware/chest-v3.5.6-usb-state-restore
3307d9678bcff5a6dc2a2ced2e33fb5660029e38 fix/back-3-13-10-usb-umbral
9dce9f49544ce6d1a54ade43536481604bfdb0ea fix/back-3-13-11-usb-pololu-off
c6e3e0eff41c8da1aef6a23f14be9869a0f4ba9f fix/back-3-13-12-nav-sig-watchdog
7b29df8e32362c1aa2d30cb740ee2062b9990779 fix/back-3-13-7-gps
903342a38a8855393ada1052d696b8b301899ae4 fix/back-3-13-8-gps-uart
6273f456f7981b6077f438c85b98ca590dca50cf fix/back-3-13-9-usb-gps-off
5a3d0348649e69daeb77cc2b83302eef497f0aa1 fix/back-3-14-0-sueno-pecho
2dd259d249765c66d939aed33bce0a1731e076bc fix/chest-v373-readfile
093b0f5760b2c15970ea3852f65c97d41226693c fix/ipad-mapa-boceto
d1128e016d1721ac6568593ea7e4c647d0f28127 fix/ipad-wifi-motivo
5d01d20b26652913a3b1efb097812cd8e9ed192d main
LISTA
echo "Etiquetas creadas: $n · ramas movidas desde la auditoría: $movidas"
echo "Siguiente paso:  git push origin --tags"
