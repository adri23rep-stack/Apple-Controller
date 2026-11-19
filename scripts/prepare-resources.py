#!/usr/bin/env python3
"""Reproduce el cliente Hydra LG con recursos fijados a un commit público."""
import hashlib
import io
import pathlib
import urllib.request
import zipfile

COMMIT = "d8451ee05b3c1f0581d9d8c4fb77e7fbe7eff06b"
URL = f"https://codeload.github.com/cristianco7/XUPER-HYDRA-PORT-WEBOS/zip/{COMMIT}"
ORIGINAL_BLOB_SHA1 = "8cd8b9bf36222d17ea663e5a0d814aba5bd08a43"
DEST = pathlib.Path("ios/Resources")
PREFIX = f"XUPER-HYDRA-PORT-WEBOS-{COMMIT}/webos/fidelity/"

print("Descargando recursos de Hydra", COMMIT, flush=True)
with urllib.request.urlopen(URL, timeout=120) as response:
    archive = response.read()
with zipfile.ZipFile(io.BytesIO(archive)) as z:
    copied = 0
    for item in z.infolist():
        if item.is_dir() or not item.filename.startswith(PREFIX):
            continue
        relative = pathlib.PurePosixPath(item.filename.removeprefix(PREFIX))
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeError("Ruta peligrosa en ZIP")
        target = DEST.joinpath(*relative.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(item))
        copied += 1
print(f"Copiados {copied} archivos.")
app = DEST / "js" / "app.js"
original = app.read_bytes()
blob = b"blob " + str(len(original)).encode() + bytes([0]) + original
actual = hashlib.sha1(blob).hexdigest()
if actual != ORIGINAL_BLOB_SHA1:
    raise RuntimeError(f"El JavaScript original cambió ({actual}); no aplicar parches sobre fuente distinta.")
source = original.decode("utf-8")
needle = '  function P(e, t, a, i) {'
assert source.count(needle) == 1, "La interfaz LG cambió: no se encontró su función de servicios"
bridge = """
    if (window.__hydraNativeCall) {
      return window.__hydraNativeCall(e, t, a);
    }
"""
app.write_text(source.replace(needle, needle + bridge, 1), encoding="utf-8")
assert (DEST / "index.html").exists() and (DEST / "data" / "portal.js").exists()
print("Cliente original + catálogo incluido + puente nativo iOS listos.")
