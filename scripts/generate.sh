#!/usr/bin/env bash
set -euo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT
upstream="$directory/upstream"
dependencies="$directory/dependencies"

curl --fail --silent --show-error --location \
	--output "$directory/kubernetes-mixin.tar.gz" \
	https://codeload.github.com/kubernetes-sigs/kubernetes-mixin/tar.gz/464d0ae592cb7d7b1c6f40741fc72fb7bb2449ac
mkdir -p "$upstream/kubernetes-mixin" "$dependencies"
tar -xzf "$directory/kubernetes-mixin.tar.gz" -C "$upstream/kubernetes-mixin" --strip-components=1
cp "$upstream/kubernetes-mixin/jsonnetfile.json" "$upstream/kubernetes-mixin/jsonnetfile.lock.json" "$dependencies/"
go build -o "$directory/jb" github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
(
	cd "$dependencies"
	"$directory/jb" install
)
if ! cmp "$upstream/kubernetes-mixin/jsonnetfile.lock.json" "$dependencies/jsonnetfile.lock.json"; then
	printf '%s\n' 'Kubernetes mixin dependencies changed from the upstream lockfile.' >&2
	exit 1
fi

go tool jsonnet -J "$upstream" -J "$dependencies/vendor" -S -c -m "$OUTPUT_DIR" mixins/main.jsonnet
CGO_ENABLED=0 go run ./cmd/formatyaml -strip-promql-comments "$OUTPUT_DIR"/*.yaml
pnpm exec oxfmt --config oxfmt.config.ts --write "$OUTPUT_DIR"
