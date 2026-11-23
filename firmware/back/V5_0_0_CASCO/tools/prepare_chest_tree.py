#!/usr/bin/env python3
"""Monta el árbol del pecho 3.7.11 ejecutando los mismos pasos de .github/workflows/build-chest-v377-despertar.yml
(hasta antes de sus pruebas). Así el casco parte siempre del pecho vigente sin copiar su cadena de parches.

Uso: python3 prepare_chest_tree.py <raíz del repositorio> <directorio temporal>
Imprime la ruta del árbol montado (la variable D del workflow del pecho).
"""
import os
import pathlib
import subprocess
import sys

import yaml

root = pathlib.Path(sys.argv[1]).resolve()
tmp = pathlib.Path(sys.argv[2]).resolve()
tmp.mkdir(parents=True, exist_ok=True)
wf = yaml.safe_load((root / ".github/workflows/build-chest-v377-despertar.yml").read_text())
env_file = tmp / "github_env"
env_file.write_text("")
env = dict(os.environ, GITHUB_WORKSPACE=str(root), RUNNER_TEMP=str(tmp), GITHUB_ENV=str(env_file))
for st in wf["jobs"]["build"]["steps"]:
    name, run = st.get("name", ""), st.get("run")
    if not run:
        continue
    if name.startswith("Static checks"):
        break
    if "diff -rq" in run:   # comprobación de ficheros cambiados del pecho: no aplica al casco
        continue
    e = dict(env)
    for k, v in (st.get("env") or {}).items():
        e[k] = str(v).replace("${{ github.workspace }}", str(root))
    for line in env_file.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            e[k] = v
    r = subprocess.run(["bash", "-c", run], env=e, cwd=root, capture_output=True, text=True)
    print(f"[pecho] {name[:90]} -> {r.returncode}", file=sys.stderr)
    if r.returncode:
        sys.stderr.write(r.stdout[-3000:] + r.stderr[-3000:])
        sys.exit(1)
d = [l.split("=", 1)[1] for l in env_file.read_text().splitlines() if l.startswith("D=")]
assert d, "el workflow del pecho no definió D"
v = (pathlib.Path(d[-1]) / "lib/avo_core/src/avo_version.h").read_text()
assert '"3.7.11"' in v, "el pecho montado no es la 3.7.11"
print(d[-1])
