#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

for script in $(find bin lib scripts tests -type f -name '*.sh' | sort); do
  bash -n "$script"
done

python3 -m json.tool config/targets.json >/dev/null

python3 - <<'PY'
import json
import re
from pathlib import Path

targets = {x["id"] for x in json.loads(Path("config/targets.json").read_text())}
workflow = Path(".github/workflows/build-release.yml").read_text()
block = workflow.split("target:", 1)[1].split("architecture:", 1)[0]
options = set(re.findall(r"^\s+- ([a-z0-9.-]+)\s*$", block, re.M))
options.discard("all")
if options != targets:
    raise SystemExit(f"Workflow target choices differ from targets.json: {options ^ targets}")
print(f"Static checks passed for {len(targets)} targets.")
PY
