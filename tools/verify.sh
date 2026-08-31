#!/usr/bin/env bash
#
# The checks that do not need a Connect IQ SDK: the board has to fit a round
# screen, and the economy has to stay a curve rather than a cliff.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${PYTHON:-}" ]; then
    for candidate in python3 python py; do
        if command -v "$candidate" >/dev/null 2>&1 &&
           "$candidate" -c "import sys" >/dev/null 2>&1; then
            PYTHON="$candidate"
            break
        fi
    done
fi
if [ -z "${PYTHON:-}" ]; then
    echo "no working python interpreter found; set PYTHON to one" >&2
    exit 1
fi

"$PYTHON" "$ROOT/tools/check_layout.py"
"$PYTHON" "$ROOT/tools/simulate_economy.py"
"$PYTHON" "$ROOT/tools/check_input.py"
