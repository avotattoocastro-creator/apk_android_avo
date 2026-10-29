#!/usr/bin/env bash
# Arranca una imagen en QEMU (Espressif, esp32c3) durante T segundos y guarda: UART0, registro de accesos no
# emulados/erróneos (-d unimp,guest_errors), registros de la CPU al final (monitor) y la línea de código del PC.
# Uso: ejecutar_qemu.sh <qemu-system-riscv32> <merged.bin> <elf> <efuse.bin> <salida/prefijo> [T=60]
set -u
Q="$1"; BIN="$2"; ELF="$3"; EF="$4"; OUT="$5"; T="${6:-60}"
cp "$EF" /tmp/efuse_$$.bin
SOCK=/tmp/qmon_$$.sock
"$Q" -nographic -machine esp32c3 -drive file="$BIN",if=mtd,format=raw \
  -drive file=/tmp/efuse_$$.bin,if=none,format=raw,id=efuse -global driver=nvram.esp32c3.efuse,property=drive,value=efuse \
  -serial file:"$OUT.uart0.log" -monitor unix:$SOCK,server,nowait -d unimp,guest_errors -D "$OUT.qemu_d.log" -gdb tcp::1234 \
  > "$OUT.qemu_stdout.txt" 2>&1 &
P=$!
sleep "$T"
python3 - "$SOCK" > "$OUT.registros.txt" 2>&1 <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.settimeout(2)
def rd():
    b = b""
    try:
        while True:
            c = s.recv(65536)
            if not c: break
            b += c
    except socket.timeout:
        pass
    return b.decode("utf-8", "replace")
rd()
for cmd in ("info registers", "info registers"):
    s.sendall((cmd + "\n").encode()); time.sleep(1); print(rd())
PY
# pila de llamadas en el punto en que está la CPU (GDB del paquete de arduino-esp32)
GDB=$(find ~/.arduino15 -name "riscv32-esp-elf-gdb" -type f | head -1)
if [ -n "$GDB" ]; then
  timeout 60 "$GDB" -q -batch -ex "set pagination off" -ex "target remote :1234" -ex "bt 30" -ex "info registers pc ra sp" \
    "$ELF" > "$OUT.pila_gdb.txt" 2>&1 || true
else
  echo "sin riscv32-esp-elf-gdb" > "$OUT.pila_gdb.txt"
fi
kill $P 2>/dev/null; wait $P 2>/dev/null
head -c 2000000 "$OUT.qemu_d.log" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT.qemu_d.log"
PC=$(grep -o -i "pc *[0-9a-f]\{8\}" "$OUT.registros.txt" | awk '{print $2}' | sort -u | tr '\n' ' ')
A2L=$(find ~/.arduino15 -name "riscv32-esp-elf-addr2line" | head -1)
{ echo "PC al final: $PC"; for p in $PC; do "$A2L" -f -p -e "$ELF" 0x$p; done; } > "$OUT.pc.txt" 2>&1
echo "== $OUT"; cat "$OUT.pc.txt"; cat "$OUT.pila_gdb.txt"; head -c 1500 "$OUT.uart0.log"; echo; sort "$OUT.qemu_d.log" | uniq -c | sort -rn | head -15
