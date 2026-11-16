#!/bin/bash
# Assemble the browser demo into build/site: the page from site/, the app's own sounds
# from Resources/, the logo, and a manifest of the sound files.
#
#   scripts/build_site.sh            # build
#   scripts/build_site.sh serve      # build + serve at http://localhost:8000
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/site
rm -rf "$OUT"
mkdir -p "$OUT/sounds"
cp site/* "$OUT/"
cp docs/logo.png "$OUT/logo.png"
cp docs/qr.png "$OUT/qr.png"
cp -R Resources/Packs "$OUT/sounds/Packs"
[[ -d Resources/Mouse ]] && cp -R Resources/Mouse "$OUT/sounds/Mouse"
find "$OUT/sounds" -name 'CREDITS.txt' -delete

python3 - "$OUT/sounds" <<'PY'
import json, os, sys
root = sys.argv[1]
audio = lambda d: sorted(f for f in os.listdir(d) if f.lower().endswith((".wav", ".mp3", ".m4a", ".ogg")))
packs = {p: audio(os.path.join(root, "Packs", p)) for p in sorted(os.listdir(os.path.join(root, "Packs")))
         if os.path.isdir(os.path.join(root, "Packs", p))}
mouse_dir = os.path.join(root, "Mouse")
manifest = {
    "default": "Gateron Red" if "Gateron Red" in packs else next(iter(packs)),
    "packs": packs,
    "mouse": audio(mouse_dir) if os.path.isdir(mouse_dir) else [],
}
json.dump(manifest, open(os.path.join(root, "manifest.json"), "w"), indent=1)
print(f"site: {len(packs)} packs, {sum(map(len, packs.values()))} key sounds, {len(manifest['mouse'])} mouse sounds")
PY

if [[ "${1:-}" == "serve" ]]; then
    echo "Serving http://localhost:8000"
    exec python3 -m http.server 8000 --bind 127.0.0.1 --directory "$OUT"
fi
