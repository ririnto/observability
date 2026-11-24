package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"cuelang.org/go/cue"
	"cuelang.org/go/cue/cuecontext"
	"cuelang.org/go/cue/errors"
)

const schemaBase = "https://raw.githubusercontent.com/grafana/grafana/v13.3.1/"

type dashboard struct {
	APIVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Metadata   struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Spec json.RawMessage `json:"spec"`
}

func main() {
	classic := flag.Bool("classic", false, "validate Classic dashboards")
	flag.Parse()
	if flag.NArg() == 0 {
		fmt.Fprintln(os.Stderr, "Usage: dashboardcheck [-classic] DASHBOARD.json [DASHBOARD.json ...]")
		os.Exit(2)
	}
	if err := check(flag.Args(), *classic); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func check(paths []string, classic bool) error {
	schemaPath := "apps/dashboard/kinds/v2/dashboard_spec.cue"
	specPath := "DashboardSpec"
	if classic {
		schemaPath = "kinds/dashboard/dashboard_kind.cue"
		specPath = "lineage.schemas[0].schema.spec"
	}

	client := http.Client{Timeout: 30 * time.Second}
	response, err := client.Get(schemaBase + schemaPath)
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
	spec := compiled.LookupPath(cue.ParsePath(specPath))
	if err := spec.Err(); err != nil {
		return fmt.Errorf("find Grafana dashboard schema: %w", err)
	}
	if classic {
		spec = spec.Unify(ctx.CompileString(`{uid!: !="", title!: !="", panels!: [_, ...]}`))
	}
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if !classic {
			var resource dashboard
			if err := json.Unmarshal(data, &resource); err != nil {
				return fmt.Errorf("%s: %w", path, err)
			}
			if resource.APIVersion != "dashboard.grafana.app/v2" || resource.Kind != "Dashboard" || resource.Metadata.Name == "" {
				return fmt.Errorf("%s: expected a named dashboard.grafana.app/v2 Dashboard", path)
			}
			data = resource.Spec
		} else if !json.Valid(data) {
			return fmt.Errorf("%s: invalid JSON", path)
		}
		if err := spec.Unify(ctx.CompileBytes(data)).Validate(cue.Final(), cue.Concrete(!classic)); err != nil {
			return fmt.Errorf("%s: %s", path, errors.Details(err, nil))
		}
		fmt.Println(path, "matches the Grafana dashboard schema")
	}
	return nil
}
