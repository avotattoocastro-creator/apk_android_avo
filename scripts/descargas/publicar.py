#!/usr/bin/env python3
"""Publica en la release fija «descargas» la última versión de cada firmware, app y CAD.

Lo lanza .github/workflows/publicar-descargas.yml. Explicación en docs/DESCARGAS_DIRECTAS.md.

- Binarios: toma el artefacto de Actions más reciente (mayor versión en el nombre y, a igualdad, el más nuevo) de una
  ejecución terminada con éxito en las ramas permitidas, y lo sube con un nombre FIJO. Así el enlace
  .../releases/download/descargas/<NOMBRE> no cambia nunca y no caduca como los artefactos.
- CAD: comprime la carpeta indicada de la rama indicada (solo STEP/STL/3MF/DXF/PDF y textos).
- Si una entrada no encuentra nada, se avisa y se conserva la descarga anterior (no se borra nada).
- Solo se vuelve a subir lo que ha cambiado (id del artefacto o hash del árbol de la carpeta).

Uso: python3 -I publicar.py <descargas.json>
Variables: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_EVENT_NAME, GITHUB_SHA, GITHUB_RUN_ID, FORZAR=true,
           SIMULAR=1 (no sube nada; deja los ficheros en ./descargas_out).
"""
from __future__ import annotations

import datetime as dt
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

REPO = os.environ.get("GITHUB_REPOSITORY", "avotattoocastro-creator/apk_android_avo")
SIMULAR = os.environ.get("SIMULAR") == "1"
FORZAR = os.environ.get("FORZAR", "").lower() == "true"
EVENTO = os.environ.get("GITHUB_EVENT_NAME", "")
SHA = os.environ.get("GITHUB_SHA", "")
RUN_ID = os.environ.get("GITHUB_RUN_ID", "")
ESTADOS_PENDIENTES = {"queued", "in_progress", "waiting", "pending", "requested"}

avisos: list[str] = []
resultados: list[dict] = []


def log(msg: str) -> None:
    print(msg, flush=True)


def aviso(msg: str) -> None:
    avisos.append(msg)
    print(f"::warning::{msg}", flush=True)


def gh(*args: str, binario: bool = False, comprobar: bool = True):
    r = subprocess.run(["gh", *args], capture_output=True, text=not binario)
    if comprobar and r.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} → {r.returncode}: {r.stderr}")
    return r


def gh_json(ruta: str):
    return json.loads(gh("api", "-H", "Accept: application/vnd.github+json", ruta).stdout)


def git(*args: str, binario: bool = False, comprobar: bool = True):
    r = subprocess.run(["git", *args], capture_output=True, text=not binario)
    if comprobar and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} → {r.returncode}: {r.stderr}")
    return r


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def version_de(nombre: str) -> tuple[int, int, int]:
    m = re.search(r"V(\d+)[-_](\d+)(?:[-_](\d+))?", nombre)
    if not m:
        return (0, 0, 0)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))


def zip_determinista(destino: Path, entradas: list[tuple[str, bytes]]) -> None:
    """ZIP con fecha fija para que el mismo contenido dé el mismo fichero."""
    with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for nombre, datos in sorted(entradas):
            info = zipfile.ZipInfo(nombre, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, datos)


# ---------------------------------------------------------------------------------------------------------------------
def esperar_compilaciones(max_min: int) -> None:
    """En un push a develop, espera a que terminen las demás compilaciones del mismo commit."""
    if EVENTO != "push" or not SHA:
        return
    limite = time.time() + max_min * 60
    while True:
        runs = gh_json(f"repos/{REPO}/actions/runs?head_sha={SHA}&per_page=100").get("workflow_runs", [])
        pendientes = [r["name"] for r in runs if str(r["id"]) != RUN_ID and r["status"] in ESTADOS_PENDIENTES]
        if not pendientes:
            log(f"Compilaciones del commit {SHA[:7]} terminadas ({len(runs)} ejecuciones).")
            return
        if time.time() > limite:
            aviso(f"Se publica sin esperar más: siguen en marcha {', '.join(pendientes)}")
            return
        log(f"Esperando a {len(pendientes)} compilaciones: {', '.join(pendientes)}")
        time.sleep(60)


def listar_artefactos(paginas: int) -> list[dict]:
    todos: list[dict] = []
    for p in range(1, paginas + 1):
        lote = gh_json(f"repos/{REPO}/actions/artifacts?per_page=100&page={p}").get("artifacts", [])
        todos.extend(lote)
        if len(lote) < 100:
            break
    return [a for a in todos if not a.get("expired")]


_conclusiones: dict[int, str] = {}


def ejecucion_ok(run_id: int) -> bool:
    if run_id not in _conclusiones:
        try:
            _conclusiones[run_id] = gh_json(f"repos/{REPO}/actions/runs/{run_id}").get("conclusion") or ""
        except RuntimeError:
            _conclusiones[run_id] = ""
    return _conclusiones[run_id] == "success"


def elegir(ent: dict, artefactos: list[dict]) -> dict | None:
    pat = re.compile(ent["nombre"])
    exc = re.compile(ent["excluir"]) if ent.get("excluir") else None
    ramas = set(ent["ramas"])
    cand = [a for a in artefactos
            if pat.search(a["name"]) and not (exc and exc.search(a["name"]))
            and (a.get("workflow_run") or {}).get("head_branch") in ramas]
    cand.sort(key=lambda a: (version_de(a["name"]), a["created_at"]), reverse=True)
    for a in cand[:15]:
        if ejecucion_ok(a["workflow_run"]["id"]):
            return a
    return None


def preparar_artefacto(ent: dict, art: dict, prohibidas: list[str], tmp: Path, out: Path) -> Path | None:
    d = tmp / ent["salida"]
    gh("run", "download", str(art["workflow_run"]["id"]), "-n", art["name"], "-D", str(d), "--repo", REPO)
    ficheros = [p for p in d.rglob("*") if p.is_file()]
    malos = [p.name for p in ficheros if p.suffix.lower() in prohibidas]
    if malos:
        aviso(f"{ent['salida']}: el artefacto {art['name']} contiene ficheros prohibidos {malos}; NO se publica")
        return None
    elegidos = [p for p in ficheros if any(fnmatch.fnmatch(p.name, g) for g in ent["archivos"])]
    if ent.get("rechazar_archivo"):
        r = re.compile(ent["rechazar_archivo"])
        rech = [p.name for p in elegidos if r.search(p.name)]
        if rech:
            aviso(f"{ent['salida']}: {rech} rechazado: {ent.get('motivo_rechazo', '')}; NO se publica")
            return None
    if not elegidos:
        aviso(f"{ent['salida']}: el artefacto {art['name']} no tiene {ent['archivos']}")
        return None
    destino = out / ent["salida"]
    if ent["tipo"] == "archivo":
        if len(elegidos) > 1:
            aviso(f"{ent['salida']}: varios candidatos {[p.name for p in elegidos]}; se toma el primero")
        shutil.copyfile(sorted(elegidos)[0], destino)
    else:
        leeme = (f"{ent['titulo']}\nArtefacto: {art['name']}\nRama: {art['workflow_run']['head_branch']}\n"
                 f"Commit: {art['workflow_run'].get('head_sha', '')}\n"
                 f"Ejecución: https://github.com/{REPO}/actions/runs/{art['workflow_run']['id']}\n"
                 "Estado: COMPILADO EN CI. Mientras no haya prueba física registrada, NO VERIFICADO en hardware.\n")
        zip_determinista(destino, [(p.relative_to(d).as_posix(), p.read_bytes()) for p in elegidos]
                         + [("ORIGEN.txt", leeme.encode())])
    return destino


def preparar_cad(pieza: dict, exts: list[str], out: Path, previo: dict | None) -> tuple[str, Path | None, dict]:
    rama, carpeta = pieza["rama"], pieza["carpeta"].strip("/")
    ref = "refs/descargas/" + re.sub(r"[^A-Za-z0-9]+", "-", rama)
    if git("fetch", "-q", "--depth", "1", "origin", f"+refs/heads/{rama}:{ref}", comprobar=False).returncode != 0:
        return ("sin_rama", None, {})
    r = git("rev-parse", f"{ref}:{carpeta}", comprobar=False)
    if r.returncode != 0:
        return ("sin_carpeta", None, {})
    arbol = r.stdout.strip()
    commit = git("rev-parse", ref).stdout.strip()
    info = {"rama": rama, "carpeta": carpeta, "arbol": arbol, "commit": commit}
    if previo and previo.get("arbol") == arbol and not FORZAR:
        return ("igual", None, info)
    nombres = [n for n in git("ls-tree", "-r", "--name-only", ref, "--", carpeta).stdout.splitlines()
               if Path(n).suffix.lower() in exts]
    if not nombres:
        return ("vacia", None, info)
    entradas = [(n[len(carpeta) + 1:], git("cat-file", "blob", f"{ref}:{n}", binario=True).stdout) for n in nombres]
    leeme = (f"{pieza['titulo']}\nRama: {rama}\nCommit: {commit}\nCarpeta: {carpeta}\n"
             f"Ficheros: {len(entradas)}\nGenerado: {dt.datetime.now(dt.timezone.utc):%Y-%m-%d %H:%M} UTC\n")
    destino = out / pieza["salida"]
    zip_determinista(destino, entradas + [("ORIGEN.txt", leeme.encode())])
    info["ficheros"] = len(entradas)
    return ("nuevo", destino, info)


# ---------------------------------------------------------------------------------------------------------------------
def main() -> int:
    cfg = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    tag = cfg["tag"]
    prohibidas = [e.lower() for e in cfg["extensiones_prohibidas"]]
    out = Path("descargas_out")
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir()
    tmp = Path(tempfile.mkdtemp(prefix="avo_descargas_"))

    # Release y manifiesto anterior.
    existe = gh("release", "view", tag, "--repo", REPO, comprobar=False).returncode == 0
    previo: dict = {}
    if existe:
        if gh("release", "download", tag, "-p", "manifiesto.json", "-D", str(tmp / "prev"), "--repo", REPO,
              comprobar=False).returncode == 0:
            previo = json.loads((tmp / "prev" / "manifiesto.json").read_text(encoding="utf-8"))
    prev_items = previo.get("items", {})

    esperar_compilaciones(cfg.get("esperar_compilaciones_min", 60))
    artefactos = listar_artefactos(cfg.get("paginas_artefactos", 10))
    log(f"{len(artefactos)} artefactos sin caducar.")

    items: dict = {}
    subir: list[Path] = []

    for ent in cfg["artefactos"]:
        s = ent["salida"]
        art = elegir(ent, artefactos)
        anterior = prev_items.get(s)
        if not art:
            estado = "conservado" if anterior else "pendiente"
            if anterior:
                items[s] = anterior
            resultados.append({"salida": s, "estado": estado, "detalle": "no hay artefacto que cumpla el filtro"})
            continue
        base = {"grupo": ent["grupo"], "titulo": ent["titulo"], "origen": "artefacto", "artefacto": art["name"],
                "artefacto_id": art["id"], "rama": art["workflow_run"]["head_branch"],
                "commit": art["workflow_run"].get("head_sha", ""), "ejecucion": art["workflow_run"]["id"],
                "fecha": art["created_at"],
                "version": ".".join(map(str, version_de(art["name"]))) if version_de(art["name"]) != (0, 0, 0) else ""}
        if anterior and anterior.get("artefacto_id") == art["id"] and not FORZAR:
            items[s] = anterior
            resultados.append({"salida": s, "estado": "igual", "detalle": art["name"]})
            continue
        try:
            p = preparar_artefacto(ent, art, prohibidas, tmp, out)
        except RuntimeError as e:
            aviso(f"{s}: no se pudo descargar {art['name']}: {e}")
            p = None
        if not p:
            if anterior:
                items[s] = anterior
            resultados.append({"salida": s, "estado": "conservado" if anterior else "error", "detalle": art["name"]})
            continue
        base.update(tamano=p.stat().st_size, sha256=sha256(p))
        items[s] = base
        subir.append(p)
        resultados.append({"salida": s, "estado": "actualizado", "detalle": art["name"]})

    exts = [e.lower() for e in cfg["cad"]["extensiones"]]
    for pieza in cfg["cad"]["piezas"]:
        s = pieza["salida"]
        anterior = prev_items.get(s)
        estado, p, info = preparar_cad(pieza, exts, out, anterior)
        if estado == "igual":
            items[s] = anterior
            resultados.append({"salida": s, "estado": "igual", "detalle": info["carpeta"]})
            continue
        if not p:
            if anterior:
                items[s] = anterior
            detalle = {"sin_rama": f"la rama {pieza['rama']} no existe",
                       "sin_carpeta": f"no existe {pieza['carpeta']} en {pieza['rama']}",
                       "vacia": f"{pieza['carpeta']} no tiene CAD"}[estado]
            resultados.append({"salida": s, "estado": "conservado" if anterior else "pendiente", "detalle": detalle})
            continue
        items[s] = {"grupo": "CAD", "titulo": pieza["titulo"], "origen": "carpeta", **info,
                    "fecha": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "tamano": p.stat().st_size, "sha256": sha256(p)}
        subir.append(p)
        resultados.append({"salida": s, "estado": "actualizado", "detalle": f"{info['ficheros']} ficheros"})

    # Manifiesto, VERSIONES.txt y notas.
    rama_int = cfg["rama_integracion"]
    manifiesto = {"generado": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "tag": tag,
                  "testflight": cfg.get("ios", {}).get("testflight_publico", ""), "items": items}
    (out / "manifiesto.json").write_text(json.dumps(manifiesto, ensure_ascii=False, indent=2), encoding="utf-8")
    base_url = f"https://github.com/{REPO}/releases/download/{tag}"
    lineas = [f"AVO Performance Horse · descargas directas · {manifiesto['generado']}", "",
              "Todo lo de aquí está COMPILADO EN CI. Que esté aquí NO significa VERIFICADO en hardware real.", ""]
    notas = [f"# {cfg['titulo']}", "",
             f"Actualizado: **{manifiesto['generado']}** · Enlaces fijos: `{base_url}/<ARCHIVO>`", "",
             "> Todo está **compilado en CI**. Estar aquí **no** significa verificado en hardware real.", ""]
    for grupo in ("Firmware", "Apps", "CAD"):
        notas += [f"## {grupo}", "", "| Archivo | Qué es | Versión / origen | Rama | Fecha |", "|---|---|---|---|---|"]
        lineas.append(f"== {grupo} ==")
        for s, it in items.items():
            if it.get("grupo") != grupo:
                continue
            fuera = "" if it.get("rama") == rama_int else " ⚠️ fuera de develop"
            origen = it.get("artefacto") or it.get("carpeta")
            ver = it.get("version") if it.get("origen") == "artefacto" else (it.get("commit") or "")[:7]
            ver = f" ({ver})" if ver else ""
            notas.append(f"| [{s}]({base_url}/{s}) | {it['titulo']} | {origen}{ver} | `{it['rama']}`{fuera} "
                         f"| {it['fecha'][:10]} |")
            lineas.append(f"{s}: {origen} · rama {it['rama']}{fuera} · commit {(it.get('commit') or '')[:7]} · "
                          f"{it['fecha'][:10]} · sha256 {it.get('sha256', '')}")
        notas.append("")
        lineas.append("")
    tf = manifiesto["testflight"]
    notas += ["## iOS / iPad", "", f"Solo por TestFlight: {tf}" if tf else
              "Solo por TestFlight (falta pegar el enlace público en `scripts/descargas/descargas.json`).", ""]
    pend = [r for r in resultados if r["estado"] in ("pendiente", "error")]
    if pend:
        notas += ["## Pendiente", ""] + [f"- `{r['salida']}`: {r['detalle']}" for r in pend] + [""]
    (out / "VERSIONES.txt").write_text("\n".join(lineas), encoding="utf-8")
    (out / "NOTAS.md").write_text("\n".join(notas), encoding="utf-8")

    # Resumen de la ejecución (sirve para ajustar los filtros).
    resumen = ["## Descargas directas", "", "| Archivo | Estado | Detalle |", "|---|---|---|"]
    resumen += [f"| {r['salida']} | {r['estado']} | {r['detalle']} |" for r in resultados]
    ultimos: dict = {}
    for a in artefactos:
        k = (a["name"], (a.get("workflow_run") or {}).get("head_branch"))
        if k not in ultimos or a["created_at"] > ultimos[k]["created_at"]:
            ultimos[k] = a
    resumen += ["", "<details><summary>Artefactos disponibles (para ajustar descargas.json)</summary>", "",
                "| Artefacto | Rama | Fecha |", "|---|---|---|"]
    resumen += [f"| {n} | {b} | {a['created_at'][:10]} |" for (n, b), a in sorted(ultimos.items(), key=lambda x: x[0])]
    resumen += ["", "</details>"]
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write("\n".join(resumen) + "\n")
    log("\n".join(resumen[: 4 + len(resultados)]))

    if SIMULAR:
        log(f"SIMULAR=1: no se sube nada. Ficheros en {out.resolve()}")
        return 0

    if not existe:
        gh("release", "create", tag, "--repo", REPO, "--target", rama_int, "--title", cfg["titulo"],
           "--notes-file", str(out / "NOTAS.md"), "--latest")
    todo = subir + [out / "VERSIONES.txt", out / "manifiesto.json"]
    for p in todo:  # de uno en uno: un fallo no tumba el resto
        try:
            gh("release", "upload", tag, str(p), "--clobber", "--repo", REPO)
            log(f"Subido {p.name} ({p.stat().st_size} B)")
        except RuntimeError as e:
            aviso(f"No se pudo subir {p.name}: {e}")
    gh("release", "edit", tag, "--repo", REPO, "--title", cfg["titulo"], "--notes-file", str(out / "NOTAS.md"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
