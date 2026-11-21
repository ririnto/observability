package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"cuelang.org/go/cue"
	"cuelang.org/go/cue/cuecontext"
	"cuelang.org/go/cue/errors"
)

const schemaURL = "https://raw.githubusercontent.com/grafana/grafana/v13.3.1/apps/dashboard/kinds/v2/dashboard_spec.cue"

type dashboard struct {
	APIVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Metadata   struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Spec json.RawMessage `json:"spec"`
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "Usage: dashboardcheck RESOURCE.json")
		os.Exit(2)
	}
	if err := check(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func check(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	var resource dashboard
	if err := json.Unmarshal(data, &resource); err != nil {
		return err
	}
	if resource.APIVersion != "dashboard.grafana.app/v2" || resource.Kind != "Dashboard" || resource.Metadata.Name == "" {
		return fmt.Errorf("%s: expected a named dashboard.grafana.app/v2 Dashboard", path)
	}

	client := http.Client{Timeout: 30 * time.Second}
	response, err := client.Get(schemaURL)
	if err != nil {
		return err
	}
	defer func() {
		_ = response.Body.Close()
	}()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("fetch Grafana schema: %s", response.Status)
	}
	schema, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return err
	}

	ctx := cuecontext.New()
	compiled := ctx.CompileBytes(schema)
	if err := compiled.Err(); err != nil {
		return fmt.Errorf("compile Grafana schema: %w", err)
	}
	spec := compiled.LookupPath(cue.ParsePath("DashboardSpec"))
	if err := spec.Err(); err != nil {
		return fmt.Errorf("find DashboardSpec: %w", err)
	}
	if err := spec.Unify(ctx.CompileBytes(resource.Spec)).Validate(cue.Concrete(true)); err != nil {
		return fmt.Errorf("%s: %s", path, errors.Details(err, nil))
	}
	fmt.Println(path, "matches Grafana v2 DashboardSpec")
	return nil
}
