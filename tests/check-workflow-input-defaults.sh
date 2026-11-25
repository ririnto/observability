#!/usr/bin/env bash
set -eo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT
go build -o "$directory/workflowcheck" ./cmd/workflowcheck
"$directory/workflowcheck" .github/workflows

cd "$directory"
if ./workflowcheck; then
	echo 'Expected workflowcheck to reject missing arguments.' >&2
	exit 1
else
	if [ "$?" -ne 2 ]; then
		echo 'Expected workflowcheck usage exit status 2.' >&2
		exit 1
	fi
fi

cat >check.yaml <<'YAML'
name: Check
on: push
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-go@v6
        with:
          cache: false
          unknown-input: ""
          cache-dependency-path: go.mod
      - uses: actions/setup-go@v6
        with:
          cache: ${{ true }}
      - uses: actions/setup-node@v6
        with:
          cache: ""
          package-manager-cache: true
      - uses: actions/checkout@v6
        with:
          ssh-key: ""
          fetch-depth: "1.0"
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0b1
      - uses: actions/setup-go@v5
        with:
          cache: true
YAML
./workflowcheck .

cat >>check.yaml <<'YAML'
      - uses: actions/setup-go@v6
        with:
          cache: &shared-cache true
      - uses: pnpm/action-setup@v4
        with: &pnpm-inputs
          cache: *shared-cache
      - uses: actions/setup-go@v6
        with: *pnpm-inputs
      - uses: actions/setup-go@v6
        with:
          cache: *shared-cache
      - uses: pnpm/action-setup@v4
        with: &other-inputs
          cache: true
      - uses: actions/setup-go@v6
        with: *other-inputs
      - uses: actions/cache@v5
        with:
          path: build-cache
          key: test-cache
          lookup-only: "false"
      - uses: actions/checkout@v6
        with:
          filter: ""
          fetch-depth: 1.0
      - uses: actions/checkout@v6
        with:
          fetch-depth: +1
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0x1
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0o1
YAML
if ./workflowcheck . 2>diagnostics; then
	echo 'Expected workflowcheck to reject redundant defaults.' >&2
	exit 1
else
	if [ "$?" -ne 1 ]; then
		cat diagnostics >&2
		exit 1
	fi
fi

cat >expected <<'EXPECTED'
check.yaml 31 actions/setup-go@v6 cache shared-cache 31
check.yaml 36 actions/setup-go@v6 cache pnpm-inputs 33
check.yaml 39 actions/setup-go@v6 cache shared-cache 31
check.yaml 44 actions/setup-go@v6 cache other-inputs 41
check.yaml 49 actions/cache@v5 lookup-only
check.yaml 52 actions/checkout@v6 filter
check.yaml 53 actions/checkout@v6 fetch-depth
check.yaml 56 actions/checkout@v6 fetch-depth
check.yaml 59 actions/checkout@v6 fetch-depth
check.yaml 62 actions/checkout@v6 fetch-depth
EXPECTED
if ! awk '
	NR == FNR {
		id = $1 SUBSEP ($2 + 0)
		expected[id] = $0
		ref[id] = $3
		input[id] = $4
		anchor[id] = $5
		definition[id] = $6
		next
	}
	{
		gsub(/[^[:alnum:]_.\/@-]+/, " ")
		id = $1 SUBSEP ($2 + 0)
		if ($2 !~ /^[0-9]+$/ || !(id in expected)) {
			print "Unexpected diagnostic at " $1 " " $2
			failed = 1
		} else {
			foundInput = 0
			foundAnchor = anchor[id] == ""
			for (i = 3; i <= NF; i++) {
				if ($i == ref[id] && $(i + 1) == input[id]) {
					foundInput = 1
				}
				if ($i == anchor[id] && $(i + 1) == $1 && $(i + 2) ~ /^[0-9]+$/ && $(i + 2) + 0 == definition[id]) {
					foundAnchor = 1
				}
			}
			if (foundInput && foundAnchor) {
				seen[id] = 1
			} else {
				print "Mismatched diagnostic for " expected[id]
				failed = 1
			}
		}
	}
	END {
		for (id in expected) {
			if (!(id in seen)) {
				print "Missing diagnostic for " expected[id]
				failed = 1
			}
		}
		exit failed
	}
' expected diagnostics; then
	cat diagnostics >&2
	exit 1
fi
