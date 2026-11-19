#!/usr/bin/env python3
"""Create an iPhone-ready JSON snapshot from the ORIGINAL pinned LG Hydra catalog."""
import hashlib
import io
import json
import pathlib
import subprocess
import urllib.request
import zipfile

COMMIT = "d8451ee05b3c1f0581d9d8c4fb77e7fbe7eff06b"
URL = f"https://codeload.github.com/cristianco7/XUPER-HYDRA-PORT-WEBOS/zip/{COMMIT}"
DEST = pathlib.Path("ios/Resources")
PREFIX = f"XUPER-HYDRA-PORT-WEBOS-{COMMIT}/webos/fidelity/"
EXPECTED_APP_HASH = "8cd8b9bf36222d17ea663e5a0d814aba5bd08a43"

print("Downloading pinned original Hydra LG sources", COMMIT, flush=True)
with urllib.request.urlopen(URL, timeout=120) as response:
    archive = response.read()
with zipfile.ZipFile(io.BytesIO(archive)) as z:
    copied = 0
    for entry in z.infolist():
        if entry.is_dir() or not entry.filename.startswith(PREFIX):
            continue
        rel = pathlib.PurePosixPath(entry.filename[len(PREFIX):])
        if rel.is_absolute() or ".." in rel.parts:
            raise RuntimeError("Invalid source archive path")
        target = DEST.joinpath(*rel.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(entry))
        copied += 1

app = (DEST / "js" / "app.js").read_bytes()
git_blob = b"blob " + str(len(app)).encode() + b"\x00" + app
assert hashlib.sha1(git_blob).hexdigest() == EXPECTED_APP_HASH, "Unexpected LG source revision"

# The portal.js file is a JavaScript object literal, not valid JSON.
# Evaluate ONLY the pinned snapshot in an isolated node:vm context, with no browser,
# process, require, filesystem or network APIs exposed to the evaluated code.
javascript = r"""
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.argv[1], 'utf8');
const isolated = { window: {} };
vm.runInNewContext(source, isolated, { timeout: 1500 });
const catalog = isolated.window.XUPERTV_PORTAL;
if (!catalog || !Array.isArray(catalog.items) || catalog.items.length < 600)
  throw new Error('Hydra LG snapshot missing or incomplete');
fs.writeFileSync(process.argv[2], JSON.stringify(catalog), 'utf8');
console.log('Hydra LG: ', catalog.items.length, 'catalog entries; source=', catalog.generatedAt);
"""
out = DEST / "hydra-catalog.json"
subprocess.run(["node", "-e", javascript, str(DEST / "data" / "portal.js"), str(out)], check=True)
catalog = json.loads(out.read_text(encoding="utf-8"))
assert catalog["source"].startswith("Magis portal")
assert len(catalog["items"]) == 610, "The catalog count changed: review it before building"
assert len({str(x["id"]) for x in catalog["items"]}) >= 500
print(f"Verified catalog from LG source: {len(catalog['items'])} entries; {copied} original assets.")
