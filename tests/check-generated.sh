#!/usr/bin/env bash
set -euo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT

go tool task generate OUTPUT_DIR="$directory"
diff -ru rendered "$directory"
