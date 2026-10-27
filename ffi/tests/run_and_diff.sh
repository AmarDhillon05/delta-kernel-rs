#!/bin/bash

set -euxo pipefail

# Usage: run_and_diff.sh <expected_file> <command> [args...]
#
# Runs the command and diffs its stdout against the expected file.
EXPECTED="$1"
shift

OUT_FILE=$(mktemp)
trap 'rm -f "$OUT_FILE"' EXIT

"$@" | tee "$OUT_FILE"
diff -s "$OUT_FILE" "$EXPECTED"
