// Command workflowcheck reports redundant literal inputs in GitHub Actions workflows.
package main

import (
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"go.yaml.in/yaml/v3"
)

type workflow struct {
	Jobs map[string]struct {
		Steps []struct {
			Uses string
			With yaml.Node
		}
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "Usage: workflowcheck WORKFLOWS_DIRECTORY")
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
	var findings []error
	for _, file := range files {
		ext := filepath.Ext(file.Name())
		if !file.IsDir() && (ext == ".yaml" || ext == ".yml") {
			findings = append(findings, checkWorkflow(filepath.Join(directory, file.Name())))
		}
	}
	return errors.Join(findings...)
}

func checkWorkflow(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var document workflow
	if err := yaml.Unmarshal(data, &document); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}

	var findings []error
	for _, job := range slices.Sorted(maps.Keys(document.Jobs)) {
		for _, step := range document.Jobs[job].Steps {
			action, ok := actionDefaults[step.Uses]
			if !ok {
				continue
			}
			inputs := &step.With
			if inputs.Kind == yaml.AliasNode {
				inputs = inputs.Alias
			}
			if inputs.Kind != yaml.MappingNode {
				continue
			}
			for i := 0; i < len(inputs.Content); i += 2 {
				key, value := inputs.Content[i], inputs.Content[i+1]
				input, ok := action.inputs[strings.ToLower(key.Value)]
				if ok && !input.contextDependent && matchesDefault(value, input.value) {
					findings = append(findings, fmt.Errorf(
						"%s:%d: R35: omit %q for %s: it equals the documented default %q at %s",
						path, key.Line, key.Value, step.Uses, input.value, action.commit,
					))
				}
			}
		}
	}
	return errors.Join(findings...)
}

func matchesDefault(node *yaml.Node, want string) bool {
	if node.Kind == yaml.AliasNode {
		node = node.Alias
	}
	if node.Kind != yaml.ScalarNode {
		return false
	}
	value := node.Value
	switch node.ShortTag() {
	case "!!null":
		value = ""
	case "!!bool":
		value = strings.ToLower(value)
	}
	return !strings.Contains(value, "${{") && value == want
}
