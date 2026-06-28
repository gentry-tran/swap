#!/usr/bin/env bash
# Run the full swap test suite: unit (per-command) + e2e (integration flow).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$HERE"/stubs/* "$HERE"/*.sh "$HERE/../swap" 2>/dev/null || true

rc=0
echo "############## UNIT ##############"
bash "$HERE/unit.sh" || rc=1
echo ""
echo "############## E2E (integration) ##############"
bash "$HERE/e2e.sh" || rc=1
echo ""
if [ "$rc" -eq 0 ]; then echo ">>> SUITE GREEN"; else echo ">>> SUITE RED"; fi
exit $rc
