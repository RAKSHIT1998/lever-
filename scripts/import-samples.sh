#!/bin/zsh
# Splits a LEVER-parsing-samples.json (exported from the app) into Tests/Fixtures/real/<n>.txt + .expected.json
# Usage: scripts/import-samples.sh ~/Downloads/LEVER-parsing-samples.json
set -e
cd "$(dirname "$0")/.."
python3 - "$1" <<'PY'
import json, sys, re, pathlib
src = pathlib.Path(sys.argv[1]); out = pathlib.Path("Tests/Fixtures/real")
out.mkdir(parents=True, exist_ok=True)
samples = json.load(open(src))
existing = len(list(out.glob("*.txt")))
for i, s in enumerate(samples, start=existing + 1):
    slug = re.sub(r"[^a-z0-9]+", "-", (s.get("merchant") or "doc").lower()).strip("-")[:24]
    name = f"{i:03d}-{slug}"
    (out / f"{name}.txt").write_text(s["rawText"])
    expected = {k: v for k, v in {
        "merchant": s.get("merchant"), "amount": s.get("amount"),
        "purchaseDate": (s.get("purchaseDate") or "")[:10] or None, "documentType": s.get("documentType"),
    }.items() if v not in (None, "", "Unknown merchant")}
    (out / f"{name}.expected.json").write_text(json.dumps(expected, indent=2))
    print(f"wrote {name}")
print(f"{len(samples)} samples → Tests/Fixtures/real")
PY
