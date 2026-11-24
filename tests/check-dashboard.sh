#!/usr/bin/env bash
set -euo pipefail

go run ./cmd/dashboardcheck rendered/static-targets.json
go run ./cmd/dashboardcheck -classic rendered/{kubernetes,node-exporter,istio}-dashboards/*.json
if result="$(go run ./cmd/dashboardcheck tests/fixtures/invalid-dashboard.json 2>&1)"; then
	printf '%s\n' 'Invalid Grafana fixture passed.' >&2
	exit 1
fi
if [[ "$result" != *'DashboardSpec.title: conflicting values'* && "$result" != *'title: conflicting values'* ]]; then
	printf '%s\n' "$result" >&2
	exit 1
fi
printf '%s\n' 'Grafana schema rejected the numeric title in the negative fixture.'
