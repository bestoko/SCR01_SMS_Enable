#!/usr/bin/env python3
"""Build release/scr01_sms_enable-v<version>.zip from module/."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "module"
OUT_DIR = ROOT / "release"

version = None
for line in (MODULE / "module.prop").read_text(encoding="utf-8").splitlines():
    if line.startswith("version="):
        version = line.split("=", 1)[1].strip()
        break
if not version:
    raise SystemExit("version= not found in module.prop")

OUT_DIR.mkdir(exist_ok=True)
out = OUT_DIR / f"scr01_sms_enable-v{version}.zip"

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(MODULE.rglob("*")):
        if path.is_file():
            zf.write(path, path.relative_to(MODULE).as_posix())

print(f"wrote {out} ({out.stat().st_size} bytes)")
