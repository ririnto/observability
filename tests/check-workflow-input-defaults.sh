#!/usr/bin/env bash
set -eo pipefail

directory="$(mktemp -d)"
trap 'rm -rf -- "$directory"' EXIT
workflows="$directory/.github/workflows"
mkdir -p "$workflows" "$directory/.github/actions/sample"

cat >"$directory/.github/actions/sample/action.yaml" <<'YAML'
name: Sample
description: Input default controls
inputs:
  empty:
    description: Null default
    default: null
  midpoint:
    description: Numeric default
    default: 100000000000001.5
  number:
    description: Numeric default
    default: 100000000000002
  plain-text:
    description: Plain string default
    default: 0b1
  text:
    description: String default
    default: '0b1'
  wide:
    description: Out-of-range hexadecimal string
    default: '0x100000000'
  missing:
    description: Omitted default
runs:
  using: composite
  steps:
    - run: echo sample
      shell: bash
YAML

touch "$workflows/00-empty.yaml"
printf '# Empty workflow\n' >"$workflows/01-comment.yaml"
printf 'name: No jobs\n' >"$workflows/02-no-jobs.yaml"
printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n' >"$workflows/03-no-steps.yaml"

cat >"$workflows/controls.yaml" <<'YAML'
name: Controls
on: push
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-go@v6
        with:
          cache: false
          unknown-input: ''
          cache-dependency-path: go.mod
      - uses: actions/setup-go@v6
        with:
          cache: ${{ true }}
      - uses: actions/setup-node@v6
        with:
          cache: ''
          package-manager-cache: true
      - uses: actions/checkout@v6
        with:
          ssh-key: ''
          fetch-depth: '1.0'
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0b1
      - uses: actions/setup-go@v5
        with:
          cache: true
  blocked:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          repository: example/other
      - uses: ./.github/actions/sample
        with:
          empty: null
  script:
    runs-on: ubuntu-latest
    steps:
      - run: git checkout other-revision
      - uses: ./.github/actions/sample
        with:
          empty: null
  missing:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/missing
        with:
          empty: null
  local:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: ./.github/actions/sample
        with:
          empty: 'null'
          midpoint: 100000000000001.4
          number: '100000000000002.0'
          plain-text: '0b2'
          text: '0b2'
          wide: 0x100000000
          missing: ''
YAML

git -C "$directory" init --quiet
git -C "$directory" add .github
tree="$(git -C "$directory" write-tree)"
commit="$(git -C "$directory" -c user.name=Fixture -c user.email=fixture@example.invalid commit-tree "$tree" -m 'Record workflow fixture')"
git -C "$directory" update-ref HEAD "$commit"

assert_records() {
	awk '
		FILENAME == ARGV[1] {
			expected[NR] = $0
			next
		}
		{
			record = $0
			gsub(/[^[:alnum:]_.\/@-]+/, " ")
			file = $1
			sub(/^.*\//, "", file)
			found = 0
			if ($2 ~ /^[0-9]+$/) {
				advice = ""
				for (k = 3; k <= NF; k++) {
					token = $k
					sub(/\.+$/, "", token)
					if (token ~ /^(omit-input|detach-and-omit|hand-edit|shared-definition)$/) {
						advice = token
					}
					tokens[token] = NR
				}
				for (i in expected) {
					fields = split(expected[i], want)
					if (file == want[1] && $2 + 0 == want[2] + 0 && tokens[want[3]] == NR &&
						(fields == 3 || tokens[want[4]] == NR) && (fields < 5 || advice == want[5])) {
						matched = 1
						for (j = 6; j <= fields; j++) {
							if (tokens[want[j]] != NR) {
								matched = 0
							}
						}
						if (matched) {
							seen[i] = 1
							found = 1
						}
					}
				}
			}
			if (!found) {
				print "Unexpected record: " record
				failed = 1
			}
		}
		END {
			for (i in expected) {
				if (!(i in seen)) {
					print "Missing record for " expected[i]
					failed = 1
				}
			}
			exit failed
		}
	' "$1" "$2"
}

go tool workflowcheck "$workflows" >"$directory/review"
assert_records /dev/stdin "$directory/review" <<'EXPECTED'
controls.yaml 35 ./.github/actions/sample
controls.yaml 42 ./.github/actions/sample
controls.yaml 48 ./.github/actions/missing
EXPECTED

go tool workflowcheck --list-metadata >"$directory/metadata"
awk '
	{
		gsub(/[^[:alnum:]_.\/@-]+/, " ")
		marked = ref = input = 0
		for (i = 1; i <= NF; i++) {
			if ($i == "actions/setup-node@v6") ref = 1
			if ($i == "package-manager-cache") input = 1
			if ($i == "context-dependent") marked = 1
		}
		if (ref && input && marked) found = 1
	}
	END { exit !found }
' "$directory/metadata"

cat >"$workflows/findings.yaml" <<'YAML'
name: Findings
on: push
env:
  USES_KEY: &uses-key uses
  WITH_KEY: &with-key with
jobs:
  validate:
    runs-on: ubuntu-latest
    steps: &steps
      - &step
        uses: actions/setup-go@v6
        with:
          cache: &default-cache true
      - uses: pnpm/action-setup@v4
        with: &value-alias-inputs
          cache: *default-cache
          dest: ~/setup-pnpm
          run_install: 'null'
      - uses: actions/setup-go@v6
        with: *value-alias-inputs
      - uses: actions/setup-go@v6
        with:
          cache: *default-cache
      - uses: actions/setup-go@v6
        with: &first-inputs
          cache: true
      - uses: pnpm/action-setup@v4
        with: *first-inputs
      - uses: actions/setup-go@v6
        with: *first-inputs
      - uses: actions/setup-go@v6
        with: &second-inputs
          cache: true
      - ? *uses-key
        : actions/setup-go@v6
        ? *with-key
        : *second-inputs
      - *step
      - uses: actions/checkout@v6
        with:
          filter: ''
          fetch-depth: 0o1
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0x1
      - uses: actions/checkout@v6
        with:
          fetch-depth: +1
      - uses: actions/cache@v5
        with:
          path: build-cache
          key: test-cache
          lookup-only: 'false'
  alias:
    runs-on: ubuntu-latest
    steps: *steps
  unused:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: &unused 1
YAML

cat >"$workflows/local.yaml" <<'YAML'
name: Local action
on: push
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: ./.github/actions/sample
        with:
          empty:
          midpoint: 100000000000002.4
          number: 100000000000001.5
          plain-text: '0b1'
          text: 0b1
YAML
git -C "$directory" add .github
tree="$(git -C "$directory" write-tree)"
commit="$(git -C "$directory" -c user.name=Fixture -c user.email=fixture@example.invalid commit-tree "$tree" -m 'Record default-equal inputs')"
git -C "$directory" update-ref HEAD "$commit"
printf 'name: Working copy only\n' >"$directory/.github/actions/sample/action.yaml"

if go tool workflowcheck "$workflows" >"$directory/review" 2>"$directory/diagnostics"; then
	printf '%s\n' 'Expected workflowcheck to reject redundant defaults.' >&2
	exit 1
else
	if [ "$?" -ne 1 ]; then
		cat "$directory/diagnostics" >&2
		exit 1
	fi
fi

if ! assert_records /dev/stdin "$directory/diagnostics" <<'EXPECTED'
findings.yaml 13 actions/setup-go@v6 cache hand-edit default-cache 16 23
findings.yaml 17 pnpm/action-setup@v4 dest shared-definition
findings.yaml 18 pnpm/action-setup@v4 run_install shared-definition
findings.yaml 20 actions/setup-go@v6 cache hand-edit value-alias-inputs default-cache 13 16 23
findings.yaml 23 actions/setup-go@v6 cache hand-edit default-cache 13 16
findings.yaml 26 actions/setup-go@v6 cache shared-definition pnpm/action-setup@v4 first-inputs
findings.yaml 30 actions/setup-go@v6 cache detach-and-omit pnpm/action-setup@v4 first-inputs
findings.yaml 33 actions/setup-go@v6 cache hand-edit second-inputs
findings.yaml 37 actions/setup-go@v6 cache detach-and-omit second-inputs uses-key with-key
findings.yaml 38 actions/setup-go@v6 cache detach-and-omit step
findings.yaml 41 actions/checkout@v6 filter hand-edit
findings.yaml 42 actions/checkout@v6 fetch-depth hand-edit
findings.yaml 45 actions/checkout@v6 fetch-depth hand-edit
findings.yaml 48 actions/checkout@v6 fetch-depth hand-edit
findings.yaml 53 actions/cache@v5 lookup-only hand-edit
findings.yaml 56 actions/setup-go@v6 cache detach-and-omit step
findings.yaml 56 actions/setup-go@v6 cache detach-and-omit first-inputs pnpm/action-setup@v4
findings.yaml 56 actions/setup-go@v6 cache detach-and-omit second-inputs
findings.yaml 56 actions/setup-go@v6 cache hand-edit value-alias-inputs default-cache
findings.yaml 56 actions/setup-go@v6 cache hand-edit default-cache
findings.yaml 56 pnpm/action-setup@v4 dest detach-and-omit
findings.yaml 56 pnpm/action-setup@v4 run_install detach-and-omit
findings.yaml 56 actions/checkout@v6 filter detach-and-omit
findings.yaml 56 actions/checkout@v6 fetch-depth detach-and-omit
findings.yaml 56 actions/cache@v5 lookup-only detach-and-omit
findings.yaml 62 actions/checkout@v6 fetch-depth omit-input unused
local.yaml 10 ./.github/actions/sample empty omit-input
local.yaml 11 ./.github/actions/sample midpoint omit-input
local.yaml 12 ./.github/actions/sample number omit-input
local.yaml 13 ./.github/actions/sample plain-text omit-input
local.yaml 14 ./.github/actions/sample text omit-input
EXPECTED
then
	cat "$directory/diagnostics" >&2
	exit 1
fi
