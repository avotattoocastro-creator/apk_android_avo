#!/bin/sh
FC=${FREECADCMD:-/home/claude/freecad_dl/squashfs-root/usr/bin/freecadcmd}
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONIOENCODING=utf-8
exec "$FC" -c "import sys; sys.argv=['$1']; __file__='$(readlink -f $1)'; exec(compile(open(__file__, encoding='utf-8').read(), __file__, 'exec'))"
