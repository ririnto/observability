package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"go.yaml.in/yaml/v3"
)

type ruleFile struct {
	Groups []struct {
		Name  string
		Rules []struct {
			Alert  string
			Title  string
			Record yaml.Node
			Labels map[string]string
		}
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "Usage: alertparity RENDERED_DIRECTORY")
		os.Exit(2)
	}
	if err := check(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func check(directory string) error {
	files, err := os.ReadDir(directory)
	if err != nil {
		return err
	}
	prometheus := make(map[string]int)
	grafana := make(map[string]int)
	for _, file := range files {
		isGrafana := strings.HasSuffix(file.Name(), "grafana-alerts.yaml")
		if !isGrafana && !strings.HasSuffix(file.Name(), "-rules.yaml") {
			continue
		}
		path := filepath.Join(directory, file.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		var rules ruleFile
		if err := yaml.Unmarshal(data, &rules); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		for _, group := range rules.Groups {
			for _, rule := range group.Rules {
				if rule.Record.Kind != 0 {
					continue
				}
				name, counts := rule.Alert, prometheus
				if isGrafana {
					name, counts = rule.Labels["prometheus_alertname"], grafana
					if name == "" {
						return fmt.Errorf("%s: Grafana alert %q is missing the prometheus_alertname label", path, rule.Title)
					}
					delete(rule.Labels, "prometheus_alertname")
				}
				delete(rule.Labels, "owner")
				labels, err := json.Marshal(rule.Labels)
				if err != nil {
					return err
				}
				counts[fmt.Sprintf("%s/%s %s", group.Name, name, labels)]++
			}
		}
	}
	var missing []string
	for _, alert := range slices.Sorted(maps.Keys(prometheus)) {
		if prometheus[alert] > grafana[alert] {
			missing = append(missing, "missing Grafana alert "+alert)
		}
	}
	for _, alert := range slices.Sorted(maps.Keys(grafana)) {
		if grafana[alert] > prometheus[alert] {
			missing = append(missing, "missing Prometheus alert "+alert)
		}
	}
	if len(missing) != 0 {
		return errors.New(strings.Join(missing, "\n"))
	}
	return nil
}
