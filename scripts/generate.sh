#!/usr/bin/env bash
set -euo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT
upstream="$directory/upstream"
dependencies="$directory/dependencies"

install_dependencies() {
	local source="$1" destination="$2" cache="$3"
	mkdir -p "$destination"
	cp "$source/jsonnetfile.json" "$source/jsonnetfile.lock.json" "$destination/"
	if [[ -n "$cache" && -d "$cache" ]]; then
		cp -R "$cache" "$destination/vendor"
	fi
	(
		cd "$destination"
		"$directory/jb" install
	)
	if ! cmp "$source/jsonnetfile.lock.json" "$destination/jsonnetfile.lock.json"; then
		printf 'Jsonnet dependencies changed from the lockfile in %s.\n' "${source##*/}" >&2
		exit 1
	fi
	if [[ -n "$cache" && ! -d "$cache" ]]; then
		cp -R "$destination/vendor" "$cache"
	fi
}

curl --fail --silent --show-error --location \
	--output "$directory/kubernetes-mixin.tar.gz" \
	https://codeload.github.com/kubernetes-sigs/kubernetes-mixin/tar.gz/464d0ae592cb7d7b1c6f40741fc72fb7bb2449ac
curl --fail --silent --show-error --location \
	--output "$directory/node-exporter.tar.gz" \
	https://codeload.github.com/prometheus/node_exporter/tar.gz/0192dd896337e6eeb5935024cd5d8aec431caf3a
curl --fail --silent --show-error --location \
	--output "$directory/grafana-jsonnet-libs.tar.gz" \
	https://codeload.github.com/grafana/jsonnet-libs/tar.gz/59b6c850610f7fa8816851c981bc76b92a55cde9
curl --fail --silent --show-error --location \
	--output "$directory/dnation-kubernetes-monitoring.tar.gz" \
	https://codeload.github.com/dNationCloud/kubernetes-monitoring/tar.gz/b00ebd69a48421f985e340bda77617319ba7b776
mkdir -p "$upstream/kubernetes-mixin" "$upstream/node-exporter" "$upstream/grafana-jsonnet-libs" "$upstream/dnation-kubernetes-monitoring"
tar -xzf "$directory/kubernetes-mixin.tar.gz" -C "$upstream/kubernetes-mixin" --strip-components=1
tar -xzf "$directory/node-exporter.tar.gz" -C "$upstream/node-exporter" --strip-components=1
tar -xzf "$directory/grafana-jsonnet-libs.tar.gz" -C "$upstream/grafana-jsonnet-libs" --strip-components=1
tar -xzf "$directory/dnation-kubernetes-monitoring.tar.gz" -C "$upstream/dnation-kubernetes-monitoring" --strip-components=1
if ! cmp "$upstream/kubernetes-mixin/jsonnetfile.json" "$upstream/node-exporter/docs/node-mixin/jsonnetfile.json"; then
	printf '%s\n' 'Node Exporter mixin dependencies differ from the locked Kubernetes mixin manifest.' >&2
	exit 1
fi
go build -o "$directory/jb" github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
install_dependencies "$upstream/kubernetes-mixin" "$dependencies/shared" "${JSONNET_VENDOR_CACHE:-}"
install_dependencies mixins/istio-dependencies "$dependencies/istio" "${ISTIO_JSONNET_VENDOR_CACHE:-}"
install_dependencies mixins/nginx-vts-dependencies "$dependencies/nginx-vts" "${NGINX_VTS_JSONNET_VENDOR_CACHE:-}"

go tool jsonnet -J "$upstream" -J "$upstream/grafana-jsonnet-libs" \
	-J "$dependencies/istio/vendor" -J "$dependencies/shared/vendor" \
	-S -c -m "$OUTPUT_DIR" mixins/main.jsonnet
go tool jsonnet -J "$upstream" -J "$dependencies/nginx-vts/vendor" \
	-S -c -m "$OUTPUT_DIR" mixins/nginx-vts.libsonnet
CGO_ENABLED=0 go run ./cmd/formatyaml -strip-promql-comments "$OUTPUT_DIR"/*.yaml
pnpm exec oxfmt --config oxfmt.config.ts --write "$OUTPUT_DIR"
