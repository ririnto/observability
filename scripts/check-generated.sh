#!/usr/bin/env bash
set -euo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT

go tool jsonnet -S -m "$directory" mixins/main.jsonnet
pnpm exec oxfmt --config oxfmt.config.ts --write "$directory"
diff -ru rendered "$directory"
