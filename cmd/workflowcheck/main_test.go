package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestWorkflowInputDefaults(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	binary := filepath.Join(dir, "workflowcheck")
	if output, err := exec.CommandContext(t.Context(), "go", "build", "-o", binary, ".").CombinedOutput(); err != nil {
		t.Fatalf("build workflowcheck: %v\n%s", err, output)
	}
	run := func(args ...string) (int, string) {
		t.Helper()
		var stderr bytes.Buffer
		cmd := exec.CommandContext(t.Context(), binary, args...)
		cmd.Stderr = &stderr
		output, err := cmd.Output()
		if cmd.ProcessState == nil || cmd.ProcessState.ExitCode() < 0 {
			t.Fatalf("run workflowcheck: %v", err)
		}
		if len(output) != 0 {
			t.Fatalf("unexpected stdout: %s", output)
		}
		return cmd.ProcessState.ExitCode(), stderr.String()
	}
	if exit, stderr := run(); exit != 2 || !strings.Contains(stderr, "workflowcheck") {
		t.Fatalf("usage exit = %d, stderr = %q", exit, stderr)
	}

	path := filepath.Join(dir, "check.yaml")
	const controls = `name: Check
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
`
	if err := os.WriteFile(path, []byte(controls), 0o600); err != nil {
		t.Fatal(err)
	}
	if exit, stderr := run(dir); exit != 0 || stderr != "" {
		t.Fatalf("controls exit = %d, stderr = %q", exit, stderr)
	}

	const defects = `      - uses: actions/setup-go@v6
        with:
          cache: &shared-cache true
      - uses: pnpm/action-setup@v4
        with: &pnpm-inputs
          cache: *shared-cache
      - uses: actions/setup-go@v6
        with: *pnpm-inputs
      - uses: actions/setup-go@v6
        with:
          cache: *shared-cache # keep the anchor
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
`
	if err := os.WriteFile(path, []byte(controls+defects), 0o600); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"cache: &shared-cache true\n":              "actions/setup-go@v6 cache edit-anchor",
		"with: *pnpm-inputs\n":                     "actions/setup-go@v6 cache edit-anchor",
		"cache: *shared-cache # keep the anchor\n": "actions/setup-go@v6 cache omit",
		"lookup-only: \"false\"\n":                 "actions/cache@v5 lookup-only omit",
		"filter: \"\"\n":                           "actions/checkout@v6 filter omit",
		"fetch-depth: 1.0\n":                       "actions/checkout@v6 fetch-depth omit",
		"fetch-depth: +1\n":                        "actions/checkout@v6 fetch-depth omit",
		"fetch-depth: 0x1\n":                       "actions/checkout@v6 fetch-depth omit",
		"fetch-depth: 0o1\n":                       "actions/checkout@v6 fetch-depth omit",
	}
	exit, stderr := run(dir)
	if exit != 1 || strings.Count(stderr, ": R35 ") != len(want) {
		t.Fatalf("want exit 1 and %d R35 findings, got exit %d and stderr:\n%s", len(want), exit, stderr)
	}
	for source, identifier := range want {
		before, _, ok := strings.Cut(controls+defects, source)
		if !ok {
			t.Fatalf("missing fixture line %q", source)
		}
		prefix := fmt.Sprintf("%s:%d: R35 %s:", path, strings.Count(before, "\n")+1, identifier)
		if strings.Count(stderr, prefix) != 1 {
			t.Errorf("want one %q diagnostic, got:\n%s", prefix, stderr)
		}
	}
	for _, anchor := range []string{"&shared-cache", "&pnpm-inputs"} {
		if strings.Count(stderr, anchor) != 1 {
			t.Errorf("want one reference to %s, got:\n%s", anchor, stderr)
		}
	}
}
