#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python -m unittest discover -s tests -p 'test_*.py' -v
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT HUP INT TERM
PYTHONPYCACHEPREFIX="$cache" python -m compileall -q axiom_harness tests

test -z "$(find . -type d -name __pycache__ -o -type f -name '*.pyc')"
printf '%s\n' ok
