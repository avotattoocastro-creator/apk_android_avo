#!/usr/bin/env bash
# Borra las ramas ya respaldadas (17/11/2026). Ejecutar desde un ordenador con acceso de escritura al repositorio:
#   bash docs/borrar_ramas_2026-11-17.sh          → solo muestra lo que haría
#   bash docs/borrar_ramas_2026-11-17.sh --borrar → borra
# Cada rama solo se borra si su etiqueta de respaldo existe y apunta EXACTAMENTE al mismo commit.
# Se conservan: develop/avo-performance-horse, main, ci/*, archivo/todo-2026-11-17 y las ramas sin etiqueta.
set -euo pipefail
REPO="https://github.com/avotattoocastro-creator/apk_android_avo.git"
MODO="${1:-}"
REMOTO=$(git ls-remote "$REPO")
sha() { printf '%s\n' "$REMOTO" | awk -v r="$1" '$2==r {print $1}'; }
borradas=0; saltadas=0
while read -r rama etiqueta; do
  [ -z "$rama" ] && continue
  s_rama=$(sha "refs/heads/$rama"); s_tag=$(sha "refs/tags/$etiqueta^{}"); [ -z "$s_tag" ] && s_tag=$(sha "refs/tags/$etiqueta")
  if [ -z "$s_rama" ]; then echo "ya no existe: $rama"; continue; fi
  if [ "$s_rama" != "$s_tag" ]; then echo "SALTADA (la rama cambió o falta etiqueta): $rama"; saltadas=$((saltadas+1)); continue; fi
  if [ "$MODO" = "--borrar" ]; then git push "$REPO" --delete "$rama" && borradas=$((borradas+1)); else echo "borraría: $rama  (respaldo: $etiqueta)"; fi
done <<'LISTA'
audit/avo-girth-pcb-revb backup/2026-11-17/audit/avo-girth-pcb-revb
cad/girth-rev5-11-cierre-magnetico backup/2026-11-17/cad/girth-rev5-11-cierre-magnetico
claude/asignacion-caballo backup/2026-11-17/claude/asignacion-caballo
claude/descargas-directas backup/2026-11-17/claude/descargas-directas
claude/integra-01-wifi-sync backup/2026-11-17/claude/integra-01-wifi-sync
claude/integra-03-pecho-3-7-10 backup/2026-11-17/claude/integra-03-pecho-3-7-10
claude/integra-04-espalda-3-14-3 backup/2026-11-17/claude/integra-04-espalda-3-14-3
claude/integra-05-licencias-2-5 backup/2026-11-17/claude/integra-05-licencias-2-5
claude/integra-06-android-2-9 backup/2026-11-17/claude/integra-06-android-2-9
claude/integra-07-ipad-motor backup/2026-11-17/claude/integra-07-ipad-motor
claude/integra-09-espalda-v4-e7 backup/2026-11-17/claude/integra-09-espalda-v4-e7
claude/integra-10-pcb-cincha-auditoria backup/2026-11-17/claude/integra-10-pcb-cincha-auditoria
claude/integra-11-pcb-cincha-aisler backup/2026-11-17/claude/integra-11-pcb-cincha-aisler
claude/ipad-camara-ancho backup/2026-11-17/claude/ipad-camara-ancho
claude/ipad-camara-avo-sync backup/2026-11-17/claude/ipad-camara-avo-sync
claude/ipad-video-datos backup/2026-11-17/claude/ipad-video-datos
claude/paridad-calendario-datos-clave backup/2026-11-17/claude/paridad-calendario-datos-clave
claude/reglas-ci-tras-integracion backup/2026-11-17/claude/reglas-ci-tras-integracion
diag/back-3-13-8-pololu-libre backup/2026-11-17/diag/back-3-13-8-pololu-libre
docs/avo-enc-1 backup/2026-11-17/docs/avo-enc-1
docs/avo-enc-1-casco backup/2026-11-17/docs/avo-enc-1-casco
docs/avo-lock-1 backup/2026-11-17/docs/avo-lock-1
docs/avo-lock-1-activar-caballos backup/2026-11-17/docs/avo-lock-1-activar-caballos
docs/avo-lock-1-alquiler backup/2026-11-17/docs/avo-lock-1-alquiler
docs/avo-lock-1-cupo-caballos backup/2026-11-17/docs/avo-lock-1-cupo-caballos
docs/avo-lock-1-decisiones backup/2026-11-17/docs/avo-lock-1-decisiones
docs/avo-lock-1-dock-qr backup/2026-11-17/docs/avo-lock-1-dock-qr
docs/avo-lock-1-jerarquia backup/2026-11-17/docs/avo-lock-1-jerarquia
docs/avo-lock-1-jerarquia-2 backup/2026-11-17/docs/avo-lock-1-jerarquia-2
docs/avo-lock-1-renovar-caballos backup/2026-11-17/docs/avo-lock-1-renovar-caballos
docs/avo-lock-1-varios-cascos backup/2026-11-17/docs/avo-lock-1-varios-cascos
export/avo-girth-aisler backup/2026-11-17/export/avo-girth-aisler
feature/android-2-8-wifi-ble backup/2026-11-17/feature/android-2-8-wifi-ble
feature/android-v1-4-ota-pecho backup/2026-11-17/feature/android-v1-4-ota-pecho
feature/android-v1-9-nfc-segments backup/2026-11-17/feature/android-v1-9-nfc-segments
feature/avo-back-rev-e7-iman backup/2026-11-17/feature/avo-back-rev-e7-iman
feature/avo-back-v4 backup/2026-11-17/feature/avo-back-v4
feature/avo-equine-2-0 backup/2026-11-17/feature/avo-equine-2-0
feature/avo-equine-intelligence-engine backup/2026-11-17/feature/avo-equine-intelligence-engine
feature/avo-firebase-sync backup/2026-11-17/feature/avo-firebase-sync
feature/avo-girth-pcb backup/2026-11-17/feature/avo-girth-pcb
feature/avo-license-nfc backup/2026-11-17/feature/avo-license-nfc
feature/avo-measurement-engine-v4 backup/2026-11-17/feature/avo-measurement-engine-v4
feature/avo-nfc-identity backup/2026-11-17/feature/avo-nfc-identity
feature/avo-ntrip-auto backup/2026-11-17/feature/avo-ntrip-auto
feature/avo-signer-android-v0.1 backup/2026-11-17/feature/avo-signer-android-v0.1
feature/avo-training-analytics backup/2026-11-17/feature/avo-training-analytics
feature/avo-usb-updater backup/2026-11-17/feature/avo-usb-updater
feature/avo-wifi-sync backup/2026-11-17/feature/avo-wifi-sync
feature/chest-3-7-7-despertar-espalda backup/2026-11-17/feature/chest-3-7-7-despertar-espalda
feature/chest-usb-pc-sync backup/2026-11-17/feature/chest-usb-pc-sync
feature/chest-v3-7-6-gnss-quality backup/2026-11-17/feature/chest-v3-7-6-gnss-quality
feature/cincha-cad-montaje backup/2026-11-17/feature/cincha-cad-montaje
feature/cincha-rev6-2-cierre backup/2026-11-17/feature/cincha-rev6-2-cierre
feature/girth-ecg-0-5-0 backup/2026-11-17/feature/girth-ecg-0-5-0
feature/girth-fw-0-4-0-bno085 backup/2026-11-17/feature/girth-fw-0-4-0-bno085
feature/girth-pcb-rev-c backup/2026-11-17/feature/girth-pcb-rev-c
feature/girth-pcb-rev-d backup/2026-11-17/feature/girth-pcb-rev-d
feature/girth-pcb-rev-d-aro backup/2026-11-17/feature/girth-pcb-rev-d-aro
feature/girth-rev5-10-pulso backup/2026-11-17/feature/girth-rev5-10-pulso
feature/girth-rev5-7-cama backup/2026-11-17/feature/girth-rev5-7-cama
feature/girth-rev5-8-1-curvas backup/2026-11-17/feature/girth-rev5-8-1-curvas
feature/girth-rev5-8-cierres backup/2026-11-17/feature/girth-rev5-8-cierres
feature/girth-rev5-9-1-pogo-medido backup/2026-11-17/feature/girth-rev5-9-1-pogo-medido
feature/girth-rev5-9-2-pogo-empotrado backup/2026-11-17/feature/girth-rev5-9-2-pogo-empotrado
feature/girth-rev5-9-pogo backup/2026-11-17/feature/girth-rev5-9-pogo
feature/hero-performance-arriba backup/2026-11-17/feature/hero-performance-arriba
feature/ipad-analisis-entreno backup/2026-11-17/feature/ipad-analisis-entreno
feature/ipad-app backup/2026-11-17/feature/ipad-app
feature/ipad-camara-menu backup/2026-11-17/feature/ipad-camara-menu
feature/ipad-carrera-analisis-profundo backup/2026-11-17/feature/ipad-carrera-analisis-profundo
feature/ipad-cuadra-carreras backup/2026-11-17/feature/ipad-cuadra-carreras
feature/ipad-flechas-carrera backup/2026-11-17/feature/ipad-flechas-carrera
feature/ipad-pdf-carrera-checks backup/2026-11-17/feature/ipad-pdf-carrera-checks
feature/ipad-pdf-carrera-entreno backup/2026-11-17/feature/ipad-pdf-carrera-entreno
feature/ipad-pdf-carrera-fila backup/2026-11-17/feature/ipad-pdf-carrera-fila
feature/ipad-pdf-carrera-saltos backup/2026-11-17/feature/ipad-pdf-carrera-saltos
feature/ipad-salir backup/2026-11-17/feature/ipad-salir
feature/logo-ajuste backup/2026-11-17/feature/logo-ajuste
feature/logo-performance-arriba backup/2026-11-17/feature/logo-performance-arriba
feature/windows-advanced-analysis backup/2026-11-17/feature/windows-advanced-analysis
feature/windows-girth-bno-units backup/2026-11-17/feature/windows-girth-bno-units
feature/windows-girth-movimiento backup/2026-11-17/feature/windows-girth-movimiento
firmware/chest-v3.5.4-sd-fix backup/2026-11-17/firmware/chest-v3.5.4-sd-fix
firmware/chest-v3.5.5-ota-usb-fix backup/2026-11-17/firmware/chest-v3.5.5-ota-usb-fix
firmware/chest-v3.5.6-usb-state-restore backup/2026-11-17/firmware/chest-v3.5.6-usb-state-restore
fix/back-3-13-10-usb-umbral backup/2026-11-17/fix/back-3-13-10-usb-umbral
fix/back-3-13-11-usb-pololu-off backup/2026-11-17/fix/back-3-13-11-usb-pololu-off
fix/back-3-13-12-nav-sig-watchdog backup/2026-11-17/fix/back-3-13-12-nav-sig-watchdog
fix/back-3-13-7-gps backup/2026-11-17/fix/back-3-13-7-gps
fix/back-3-13-8-gps-uart backup/2026-11-17/fix/back-3-13-8-gps-uart
fix/back-3-13-9-usb-gps-off backup/2026-11-17/fix/back-3-13-9-usb-gps-off
fix/back-3-14-0-sueno-pecho backup/2026-11-17/fix/back-3-14-0-sueno-pecho
fix/chest-v373-readfile backup/2026-11-17/fix/chest-v373-readfile
fix/girth-revd-cpl-centros backup/2026-11-17/fix/girth-revd-cpl-centros
fix/ipad-mapa-boceto backup/2026-11-17/fix/ipad-mapa-boceto
fix/ipad-wifi-hotspot-entitlement backup/2026-11-17/fix/ipad-wifi-hotspot-entitlement
fix/ipad-wifi-motivo backup/2026-11-17/fix/ipad-wifi-motivo
fix/ipad-wifi-motivos-rechazo backup/2026-11-17/fix/ipad-wifi-motivos-rechazo
LISTA
echo "Borradas: $borradas · saltadas: $saltadas"
