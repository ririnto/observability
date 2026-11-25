package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWorkflowInputDefaults(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
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
      - uses: actions/setup-go@v5
        with:
          cache: true
`
	if err := os.WriteFile(path, []byte(controls), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := check(dir); err != nil {
		t.Fatalf("controls should pass: %v", err)
	}

	const defect = `      - uses: actions/setup-go@v6
        with:
          cache: true
      - uses: actions/cache@v5
        with:
          path: build-cache
          key: test-cache
          lookup-only: "false"
      - uses: actions/checkout@v6
        with:
          filter: ""
`
	if err := os.WriteFile(path, []byte(controls+defect), 0o600); err != nil {
		t.Fatal(err)
	}
	err := check(dir)
	if err == nil {
		t.Fatal("redundant defaults should fail")
	}
	diagnostics := strings.Split(err.Error(), "\n")
	if len(diagnostics) != 3 {
		t.Fatalf("want three R35 diagnostics, got %v", diagnostics)
	}
	if !strings.Contains(diagnostics[0], `R35: omit "cache" for actions/setup-go@v6`) ||
		!strings.Contains(diagnostics[1], `R35: omit "lookup-only" for actions/cache@v5`) ||
		!strings.Contains(diagnostics[2], `R35: omit "filter" for actions/checkout@v6`) {
		t.Fatalf("unexpected diagnostics: %v", diagnostics)
	}
}
