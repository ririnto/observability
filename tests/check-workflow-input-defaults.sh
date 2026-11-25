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
    description: Hexadecimal default
    default: 0x100000000
  high-bit:
    description: Positive decimal default
    default: 2147483648
  wide-octal:
    description: Positive decimal default
    default: 4294967296
  octal:
    description: Octal default
    default: 0o100
  negative:
    description: Negative decimal default
    default: -2147483648
  negative-hex:
    description: Negative decimal default
    default: -2147483648
  negative-octal:
    description: Octal default with its high bit set
    default: 0o20000000000
  rounded:
    description: Decimal default
    default: 1000000000000000
  adjacent:
    description: Decimal default
    default: 1000000000000002
  integer-midpoint:
    description: Decimal default
    default: 1000000000000005
  exact-rounding:
    description: Decimal default
    default: 100000000000001000
  double-rounding:
    description: Decimal default
    default: 100000000000000500
  distinct-number:
    description: Decimal default
    default: 100000000000002
  g15-text:
    description: Formatted number default
    default: '1E+15'
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
          package-manager-cache: false
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
          wide: '0x100000000'
          negative: 2147483648
          rounded: -1000000000000001
          missing: ''
YAML

git -C "$directory" init --quiet
git -C "$directory" add .github
tree="$(git -C "$directory" write-tree)"
commit="$(git -C "$directory" -c user.name=Fixture -c user.email=fixture@example.invalid commit-tree "$tree" -m 'Record workflow fixture')"
git -C "$directory" update-ref HEAD "$commit"

assert_records() {
	awk '
		function assign(record_number,   candidate) {
			for (candidate in expected) {
				if ((record_number, candidate) in compatible && visited[candidate] != NR) {
					visited[candidate] = NR
					if (!(candidate in assigned) || assign(assigned[candidate])) {
						assigned[candidate] = record_number
						return 1
					}
				}
			}
			return 0
		}
		FILENAME == ARGV[1] {
			expected[NR] = $0
			next
		}
		{
			record = $0
			gsub(/[^[:alnum:]_.\/@-]+/, " ")
			file = $1
			sub(/^.*\//, "", file)
			if ($2 ~ /^[0-9]+$/) {
				advice = ""
				for (k = 3; k <= NF; k++) {
					token = $k
					sub(/\.+$/, "", token)
					if (advice == "") {
						if (token ~ /^(omit-input|detach-and-omit|hand-edit|shared-definition)$/) {
							advice = token
						} else {
							identity[token] = NR
						}
					}
					tokens[token] = NR
				}
				for (i in expected) {
					fields = split(expected[i], want)
					if (file == want[1] && $2 + 0 == want[2] + 0 && identity[want[3]] == NR &&
						(fields == 3 || identity[want[4]] == NR) && (fields < 5 || advice == want[5])) {
						matched = 1
						for (j = 6; j <= fields; j++) {
							if (tokens[want[j]] != NR) {
								matched = 0
							}
						}
						if (matched) {
							compatible[NR, i] = 1
						}
					}
				}
			}
			if (!assign(NR)) {
				print "Unexpected record: " record
				failed = 1
			}
		}
		END {
			for (i in expected) {
				if (!(i in assigned)) {
					print "Missing record for " expected[i]
					failed = 1
				}
			}
			exit failed
		}
	' "$1" "$2"
}

cat >"$directory/expected" <<'EXPECTED'
scratch.yaml 10 actions/setup-go@v6 cache hand-edit inputs default-cache
scratch.yaml 10 actions/setup-go@v6 cache hand-edit default-cache
EXPECTED
cat >"$directory/complete" <<'DIAGNOSTICS'
scratch.yaml:10: R35 actions/setup-go@v6 cache [hand-edit]: preserve inputs and default-cache
scratch.yaml:10: R35 actions/setup-go@v6 cache [hand-edit]: preserve default-cache
DIAGNOSTICS
assert_records "$directory/expected" "$directory/complete"
awk 'NR == 1 { first = $0 } NR == 2 { print; print first }' "$directory/complete" >"$directory/reversed"
assert_records "$directory/expected" "$directory/reversed"
head -n 1 "$directory/complete" >"$directory/incomplete"
if assert_records "$directory/expected" "$directory/incomplete" >"$directory/matcher-failure"; then
	printf '%s\n' 'Expected the diagnostic matcher to reject a missing record.' >&2
	exit 1
else
	matcher_status=$?
	if [ "$matcher_status" -ne 1 ]; then
		cat "$directory/matcher-failure" >&2
		exit 1
	fi
	printf 'Diagnostic matcher rejected scratch output with one record removed (exit %s).\n' "$matcher_status"
fi

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
		for (i = 1; i <= NF; i++) {
			token = $i
			sub(/\.+$/, "", token)
			tokens[token] = NR
		}
		if (tokens["actions/setup-node@v6"] == NR) {
			if (tokens["architecture"] == NR && tokens["context-dependent"] == NR) {
				marked = 1
			}
			if (tokens["package-manager-cache"] == NR && tokens["literal"] == NR && tokens["true"] == NR) {
				literal = 1
			}
		}
	}
	END { exit !(marked && literal) }
' "$directory/metadata"

cat >>"$workflows/controls.yaml" <<'YAML'
  staged:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/sample
        with:
          empty: null
YAML
git -C "$directory" add .github/workflows/controls.yaml

if go tool workflowcheck "$workflows" >"$directory/review" 2>"$directory/diagnostics"; then
	cat "$directory/review" >&2
	printf '%s\n' 'Expected a redundant input finding in the staged workflow.' >&2
	exit 1
else
	test "$?" -eq 1
fi
assert_records /dev/stdin "$directory/diagnostics" <<'EXPECTED'
controls.yaml 71 ./.github/actions/sample empty omit-input
EXPECTED
assert_records /dev/stdin "$directory/review" <<'EXPECTED'
controls.yaml 35 ./.github/actions/sample
controls.yaml 42 ./.github/actions/sample
controls.yaml 48 ./.github/actions/missing
EXPECTED

assert_staged_workflow_left_to_review() {
	go tool workflowcheck "$workflows" >"$directory/review" 2>"$directory/diagnostics"
	test ! -s "$directory/diagnostics"
	assert_records /dev/stdin "$directory/review" <<'EXPECTED'
controls.yaml 35 ./.github/actions/sample
controls.yaml 42 ./.github/actions/sample
controls.yaml 48 ./.github/actions/missing
controls.yaml 55 ./.github/actions/sample
controls.yaml 69 ./.github/actions/sample
EXPECTED
}

printf 'name: Working copy only\n' >"$directory/.github/actions/sample/action.yaml"
assert_staged_workflow_left_to_review
git -C "$directory" add .github/actions/sample/action.yaml
git -C "$directory" restore --source=HEAD --worktree -- .github/actions/sample/action.yaml
assert_staged_workflow_left_to_review
git -C "$directory" restore --staged --worktree -- .github/actions/sample/action.yaml .github/workflows/controls.yaml

cat >"$workflows/findings.yaml" <<'YAML'
name: Findings
on: push
env:
  USES_KEY: &uses-key uses
  WITH_KEY: &with-key with
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - &step
        uses: &setup-go actions/setup-go@v6
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
      - uses: actions/setup-node@v6
        with:
          package-manager-cache: true
  unused:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: &unused 1
  keys-and-ref:
    runs-on: ubuntu-latest
    steps:
      - uses: *setup-go
        with:
          cache: true
      - uses: actions/checkout@v6
        ? *with-key
        :
          fetch-depth: 1
      - ? *uses-key
        : actions/checkout@v6
        with:
          fetch-depth: 1
YAML

cat >"$workflows/sequence.yaml" <<'YAML'
name: Steps alias
on: push
env:
  DEPTH: &depth 1
jobs:
  validate: &job
    runs-on: ubuntu-latest
    steps: &steps
      - &step
        uses: actions/checkout@v6
        with:
          filter: ''
          fetch-depth: *depth
  alias:
    runs-on: ubuntu-latest
    steps: *steps
  step-alias:
    runs-on: ubuntu-latest
    steps: &reused-steps
      - *step
  nested:
    runs-on: ubuntu-latest
    steps: *reused-steps
  job-alias: *job
YAML

cat >"$workflows/nested.yaml" <<'YAML'
name: Nested aliases
on: push
env:
  KEY: &input-key fetch-depth
  DEPTH: &depth 1
  OTHER_DEPTH: &other-depth 2
  EXPRESSION: &expression ${{ github.run_number }}
jobs:
  define:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with: &inputs
          filter: ''
          ? *input-key
          : *depth
      - uses: actions/setup-go@v6
        with: *inputs
      - uses: actions/checkout@v6
        with:
          fetch-depth: *other-depth
      - uses: actions/checkout@v6
        with:
          fetch-depth: *expression
      - uses: actions/checkout@v6
        with:
          fetch-depth: *inputs
  consume:
    runs-on: ubuntu-latest
    steps: &steps
      - &step
        uses: actions/checkout@v6
        with: *inputs
  step-alias:
    runs-on: ubuntu-latest
    steps: &reused-steps
      - *step
  sequence-alias:
    runs-on: ubuntu-latest
    steps: *steps
  nested: &job
    runs-on: ubuntu-latest
    steps: *reused-steps
  job-alias: *job
  key-alias:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          ? *input-key
          : 1
YAML

cat >"$workflows/jobs-alias.yaml" <<'YAML'
name: Jobs mapping alias
on: push
env:
  DEPTH: &depth 1
x-template: &job-map
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          filter: ''
          fetch-depth: *depth
jobs: *job-map
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
          wide: 4294967296
          high-bit: 0x80000000
          wide-octal: 0o40000000000
          octal: 64
          negative: -02147483648
          negative-hex: 0x80000000
          negative-octal: -2147483648
          rounded: 1000000000000001
          adjacent: 1000000000000001
          integer-midpoint: 1000000000000000
          exact-rounding: 100000000000000501
          g15-text: 1000000000000001
          double-rounding: 100000000000000501
          distinct-number: 100000000000003
YAML
git -C "$directory" add .github
tree="$(git -C "$directory" write-tree)"
commit="$(git -C "$directory" -c user.name=Fixture -c user.email=fixture@example.invalid commit-tree "$tree" -m 'Record default-equal inputs')"
git -C "$directory" update-ref HEAD "$commit"

assert_redundant_defaults() {
	if go tool workflowcheck "$workflows" >"$directory/review" 2>"$directory/diagnostics"; then
		printf '%s\n' 'Expected workflowcheck to reject redundant defaults.' >&2
		exit 1
	else
		if [ "$?" -ne 1 ]; then
			cat "$directory/diagnostics" >&2
			exit 1
		fi
	fi
}

cat >"$directory/expected-findings" <<'EXPECTED'
findings.yaml 13 actions/setup-go@v6 cache hand-edit default-cache 16 23
findings.yaml 17 pnpm/action-setup@v4 dest shared-definition
findings.yaml 18 pnpm/action-setup@v4 run_install shared-definition
findings.yaml 20 actions/setup-go@v6 cache detach-and-omit value-alias-inputs default-cache 13 16 23
findings.yaml 23 actions/setup-go@v6 cache hand-edit default-cache 13 16
findings.yaml 26 actions/setup-go@v6 cache shared-definition pnpm/action-setup@v4 first-inputs
findings.yaml 30 actions/setup-go@v6 cache detach-and-omit pnpm/action-setup@v4 first-inputs
findings.yaml 33 actions/setup-go@v6 cache hand-edit second-inputs
findings.yaml 37 actions/setup-go@v6 cache detach-and-omit second-inputs uses-key with-key
findings.yaml 38 actions/setup-go@v6 cache detach-and-omit step
findings.yaml 41 actions/checkout@v6 filter omit-input
findings.yaml 42 actions/checkout@v6 fetch-depth omit-input
findings.yaml 45 actions/checkout@v6 fetch-depth omit-input
findings.yaml 48 actions/checkout@v6 fetch-depth omit-input
findings.yaml 53 actions/cache@v5 lookup-only omit-input
findings.yaml 56 actions/setup-node@v6 package-manager-cache omit-input
findings.yaml 62 actions/checkout@v6 fetch-depth omit-input unused
findings.yaml 68 actions/setup-go@v6 cache hand-edit setup-go
findings.yaml 72 actions/checkout@v6 fetch-depth hand-edit with-key
findings.yaml 76 actions/checkout@v6 fetch-depth hand-edit uses-key
local.yaml 10 ./.github/actions/sample empty omit-input
local.yaml 11 ./.github/actions/sample midpoint omit-input
local.yaml 12 ./.github/actions/sample number omit-input
local.yaml 13 ./.github/actions/sample plain-text omit-input
local.yaml 14 ./.github/actions/sample text omit-input
local.yaml 18 ./.github/actions/sample octal omit-input
local.yaml 19 ./.github/actions/sample negative omit-input
local.yaml 20 ./.github/actions/sample negative-hex omit-input
local.yaml 21 ./.github/actions/sample negative-octal omit-input
local.yaml 22 ./.github/actions/sample rounded omit-input
local.yaml 23 ./.github/actions/sample adjacent omit-input
local.yaml 24 ./.github/actions/sample integer-midpoint omit-input
local.yaml 26 ./.github/actions/sample g15-text omit-input
local.yaml 27 ./.github/actions/sample double-rounding omit-input
jobs-alias.yaml 13 actions/checkout@v6 filter detach-and-omit job-map
jobs-alias.yaml 13 actions/checkout@v6 fetch-depth detach-and-omit job-map depth
nested.yaml 14 actions/checkout@v6 filter shared-definition inputs actions/setup-go@v6
nested.yaml 16 actions/checkout@v6 fetch-depth hand-edit inputs input-key depth actions/setup-go@v6
nested.yaml 33 actions/checkout@v6 filter detach-and-omit inputs step steps actions/setup-go@v6
nested.yaml 33 actions/checkout@v6 fetch-depth detach-and-omit inputs step steps input-key depth actions/setup-go@v6
nested.yaml 37 actions/checkout@v6 filter detach-and-omit inputs step reused-steps
nested.yaml 37 actions/checkout@v6 fetch-depth detach-and-omit inputs step reused-steps input-key depth
nested.yaml 40 actions/checkout@v6 filter detach-and-omit inputs step steps
nested.yaml 40 actions/checkout@v6 fetch-depth detach-and-omit inputs step steps input-key depth
nested.yaml 43 actions/checkout@v6 filter detach-and-omit inputs step reused-steps job
nested.yaml 43 actions/checkout@v6 fetch-depth detach-and-omit inputs step reused-steps job input-key depth
nested.yaml 44 actions/checkout@v6 filter detach-and-omit inputs step reused-steps job
nested.yaml 44 actions/checkout@v6 fetch-depth detach-and-omit inputs step reused-steps job input-key depth
nested.yaml 50 actions/checkout@v6 fetch-depth hand-edit input-key
sequence.yaml 12 actions/checkout@v6 filter hand-edit job steps step
sequence.yaml 13 actions/checkout@v6 fetch-depth hand-edit job steps step depth
sequence.yaml 16 actions/checkout@v6 filter detach-and-omit steps step
sequence.yaml 16 actions/checkout@v6 fetch-depth detach-and-omit steps step depth
sequence.yaml 20 actions/checkout@v6 filter detach-and-omit step reused-steps
sequence.yaml 20 actions/checkout@v6 fetch-depth detach-and-omit step reused-steps depth
sequence.yaml 23 actions/checkout@v6 filter detach-and-omit step reused-steps
sequence.yaml 23 actions/checkout@v6 fetch-depth detach-and-omit step reused-steps depth
sequence.yaml 24 actions/checkout@v6 filter detach-and-omit job steps step
sequence.yaml 24 actions/checkout@v6 fetch-depth detach-and-omit job steps step depth
EXPECTED

assert_redundant_defaults
assert_records "$directory/expected-findings" "$directory/diagnostics"

printf 'name: Working copy only\n' >"$directory/.github/actions/sample/action.yaml"
assert_redundant_defaults
awk '$1 != "local.yaml"' "$directory/expected-findings" >"$directory/expected-external"
assert_records "$directory/expected-external" "$directory/diagnostics"
assert_records /dev/stdin "$directory/review" <<'EXPECTED'
controls.yaml 35 ./.github/actions/sample
controls.yaml 42 ./.github/actions/sample
controls.yaml 48 ./.github/actions/missing
controls.yaml 55 ./.github/actions/sample
local.yaml 8 ./.github/actions/sample
EXPECTED
