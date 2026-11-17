#!/usr/bin/env python3
"""Archiva en el repositorio la última versión de cada artefacto de GitHub Actions.

Se ejecuta dentro de GitHub Actions (workflow archivar-artefactos.yml) con GH_TOKEN.
Para cada nombre de artefacto no caducado descarga el más reciente y lo guarda en
archivo/binarios/<categoría>/<nombre>/<nombre>.zip con un README.md de origen,
y genera archivo/binarios/INDICE.md. Hace un commit y un push por categoría.
"""
import hashlib
import json
import os
import subprocess
import sys

REPO = os.environ["GITHUB_REPOSITORY"]
RAIZ = "archivo/binarios"


def gh(*args, out=None):
    if out:
        with open(out, "wb") as f:
            subprocess.run(["gh", *args], check=True, stdout=f)
        return None
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def git(*args):
    subprocess.run(["git", *args], check=True)


def categoria(n):
    u = n.upper()
    if "PCB" in u or "DOCK" in u or u.startswith("AUDITORIA") or u.endswith("-CAD"):
        return "hardware"
    if "CHEST" in u:
        return "firmware_pecho"
    if "BACK" in u:
        return "firmware_espalda"
    if "GIRTH" in u:
        return "firmware_cincha"
    if "UPDATE" in u:
        return "app_avo_update"
    if "WINDOWS" in u:
        return "app_windows"
    if "IPAD" in u:
        return "app_ipad"
    if u.startswith("EQUINE"):
        return "motor_equine"
    if "PERFORMANCE-HORSE" in u or "SIGNER" in u or "ANDROID" in u:
        return "app_android"
    return "informes_ci"


def main():
    arts = []
    page = 1
    while True:
        d = json.loads(gh("api", f"repos/{REPO}/actions/artifacts?per_page=100&page={page}"))
        if not d["artifacts"]:
            break
        arts += [a for a in d["artifacts"] if not a["expired"]]
        page += 1
    ultimos = {}
    for a in sorted(arts, key=lambda a: a["created_at"], reverse=True):
        ultimos.setdefault(a["name"], a)
    print(f"{len(arts)} artefactos vigentes, {len(ultimos)} nombres distintos")

    porcat = {}
    for n, a in ultimos.items():
        porcat.setdefault(categoria(n), []).append(a)

    filas = []
    for cat in sorted(porcat):
        for a in sorted(porcat[cat], key=lambda a: a["name"]):
            n = a["name"]
            carpeta = f"{RAIZ}/{cat}/{n}"
            os.makedirs(carpeta, exist_ok=True)
            destino = f"{carpeta}/{n}.zip"
            try:
                gh("api", f"repos/{REPO}/actions/artifacts/{a['id']}/zip", out=destino)
            except subprocess.CalledProcessError:
                print(f"AVISO: no se pudo descargar {n}", file=sys.stderr)
                continue
            sha = hashlib.sha256(open(destino, "rb").read()).hexdigest()
            run = a.get("workflow_run") or {}
            with open(f"{carpeta}/README.md", "w") as f:
                f.write(
                    f"# {n}\n\n"
                    f"Copia permanente del artefacto de GitHub Actions (el original caducaba el {a['expires_at'][:10]}).\n\n"
                    f"| Dato | Valor |\n|---|---|\n"
                    f"| Rama | `{run.get('head_branch', '?')}` |\n"
                    f"| Commit | `{run.get('head_sha', '?')}` |\n"
                    f"| Run | {run.get('id', '?')} |\n"
                    f"| Creado | {a['created_at']} |\n"
                    f"| Tamaño | {a['size_in_bytes']} B |\n"
                    f"| SHA-256 del zip | `{sha}` |\n\n"
                    "Estado: **compilado en CI**. Que esté aquí no significa que esté verificado en hardware real.\n"
                )
            filas.append((cat, n, run.get("head_branch", "?"), (run.get("head_sha") or "?")[:7], a["created_at"][:10], sha[:12]))
        git("add", f"{RAIZ}/{cat}")
        git("commit", "-q", "-m", f"Archivo binarios: {cat} ({len(porcat[cat])} artefactos) [skip ci]")
        git("push", "-q", "origin", f"HEAD:refs/heads/{os.environ['GITHUB_REF_NAME']}")
        print(f"subido {cat}")

    with open(f"{RAIZ}/INDICE.md", "w") as f:
        f.write("# Índice de binarios archivados\n\nÚltima versión de cada artefacto de GitHub Actions, copiada al repositorio "
                "para que no caduque. Todo es **compilado en CI**, no verificado en hardware salvo que su documentación diga lo contrario.\n\n"
                "| Categoría | Artefacto | Rama | Commit | Fecha | SHA-256 (12) |\n|---|---|---|---|---|---|\n")
        for fila in filas:
            cat, n, rama, c, fecha, sha = fila
            f.write(f"| {cat} | [{n}]({cat}/{n}/) | `{rama}` | `{c}` | {fecha} | `{sha}` |\n")
    git("add", f"{RAIZ}/INDICE.md")
    git("commit", "-q", "-m", "Archivo binarios: índice [skip ci]")
    git("push", "-q", "origin", f"HEAD:refs/heads/{os.environ['GITHUB_REF_NAME']}")


if __name__ == "__main__":
    main()
