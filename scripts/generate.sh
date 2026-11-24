#!/usr/bin/env bash
set -euo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT

curl --fail --silent --show-error --location \
	--output "$directory/kubernetes-mixin.tar.gz" \
	https://codeload.github.com/kubernetes-sigs/kubernetes-mixin/tar.gz/464d0ae592cb7d7b1c6f40741fc72fb7bb2449ac
mkdir "$directory/kubernetes-mixin"
tar -xzf "$directory/kubernetes-mixin.tar.gz" -C "$directory/kubernetes-mixin" --strip-components=1
cp "$directory/kubernetes-mixin/jsonnetfile.lock.json" "$directory/locked.json"
go build -o "$directory/jb" github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
(
	cd "$directory/kubernetes-mixin"
	"$directory/jb" install
)
if ! cmp "$directory/locked.json" "$directory/kubernetes-mixin/jsonnetfile.lock.json"; then
	printf '%s\n' 'Kubernetes mixin dependencies changed from the upstream lockfile.' >&2
	exit 1
fi

go tool jsonnet -J "$directory" -J "$directory/kubernetes-mixin/vendor" -S -c -m "$OUTPUT_DIR" mixins/main.jsonnet
go run ./cmd/formatyaml "$OUTPUT_DIR"/*.yaml
pnpm exec oxfmt --config oxfmt.config.ts --write "$OUTPUT_DIR"
