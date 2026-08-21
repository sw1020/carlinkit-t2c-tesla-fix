#!/usr/bin/env bash
set -euo pipefail

HOST="${T2C_HOST:-192.168.3.1}"
JSON="$(curl -fsS "http://${HOST}/cgi-bin/index.cgi?id=host")"

python3 - "$JSON" <<'PY'
import json, sys
j = json.loads(sys.argv[1])
print("T2C compatibility information")
print("-----------------------------")
print("appver:", (j.get("sys") or {}).get("appver", "<unknown>"))
print("update state:", j.get("update", "<unknown>"))
print("resolution mode (pix):", j.get("pix", "<unknown>"))
print()
print("Sensitive device identifiers intentionally omitted.")
PY
