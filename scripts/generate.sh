#!/usr/bin/env bash
set -euo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT
upstream="$directory/upstream"
dependencies="$directory/dependencies"

curl --fail --silent --show-error --location \
	--output "$directory/kubernetes-mixin.tar.gz" \
	https://codeload.github.com/kubernetes-sigs/kubernetes-mixin/tar.gz/464d0ae592cb7d7b1c6f40741fc72fb7bb2449ac
curl --fail --silent --show-error --location \
	--output "$directory/node-exporter.tar.gz" \
	https://codeload.github.com/prometheus/node_exporter/tar.gz/0192dd896337e6eeb5935024cd5d8aec431caf3a
mkdir -p "$upstream/kubernetes-mixin" "$upstream/node-exporter" "$dependencies"
tar -xzf "$directory/kubernetes-mixin.tar.gz" -C "$upstream/kubernetes-mixin" --strip-components=1
tar -xzf "$directory/node-exporter.tar.gz" -C "$upstream/node-exporter" --strip-components=1
if ! cmp "$upstream/kubernetes-mixin/jsonnetfile.json" "$upstream/node-exporter/docs/node-mixin/jsonnetfile.json"; then
	printf '%s\n' 'Node Exporter mixin dependencies differ from the locked Kubernetes mixin manifest.' >&2
	exit 1
fi
cp "$upstream/kubernetes-mixin/jsonnetfile.json" "$upstream/kubernetes-mixin/jsonnetfile.lock.json" "$dependencies/"
if [[ -n "${JSONNET_VENDOR_CACHE:-}" && -d "$JSONNET_VENDOR_CACHE" ]]; then
	cp -R "$JSONNET_VENDOR_CACHE" "$dependencies/vendor"
fi
go build -o "$directory/jb" github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
(
	cd "$dependencies"
	"$directory/jb" install
)
if ! cmp "$upstream/kubernetes-mixin/jsonnetfile.lock.json" "$dependencies/jsonnetfile.lock.json"; then
	printf '%s\n' 'Kubernetes mixin dependencies changed from the upstream lockfile.' >&2
	exit 1
fi
if [[ -n "${JSONNET_VENDOR_CACHE:-}" && ! -d "$JSONNET_VENDOR_CACHE" ]]; then
	cp -R "$dependencies/vendor" "$JSONNET_VENDOR_CACHE"
fi

go tool jsonnet -J "$upstream" -J "$dependencies/vendor" -S -c -m "$OUTPUT_DIR" mixins/main.jsonnet
CGO_ENABLED=0 go run ./cmd/formatyaml -strip-promql-comments "$OUTPUT_DIR"/*.yaml
pnpm exec oxfmt --config oxfmt.config.ts --write "$OUTPUT_DIR"
