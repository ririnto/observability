// Command workflowcheck checks workflow inputs against approved action metadata without network access.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

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
	var document yaml.Node
	if err := yaml.Unmarshal(data, &document); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	if len(document.Content) == 0 {
		return nil
	}

	root := yamlSource{node: document.Content[0], aliases: referencedAnchors(&document)}
	jobs := root.field("jobs")
	var findings []error
	for _, job := range mappingPairs(jobs.node) {
		steps := jobs.child(job).field("steps")
		if steps.node != nil && steps.node.Kind == yaml.SequenceNode {
			for _, step := range steps.node.Content {
				findings = append(findings, checkStep(path, steps.child(step))...)
			}
		}
	}
	return errors.Join(findings...)
}

func checkStep(path string, step yamlSource) []error {
	uses := step.field("uses").node
	if uses == nil {
		return nil
	}
	action, ok := actionDefaults[uses.Value]
	if !ok {
		return nil
	}

	var findings []error
	inputs := step.field("with")
	for key, value := range mappingPairs(inputs.node) {
		name := resolveAlias(key).Value
		input, ok := action.inputs[strings.ToLower(name)]
		if ok && input.kind == literalDefault && matchesDefault(value, input.value) {
			line, anchor := key.Line, inputs.anchor
			if inputs.aliasLine != 0 {
				line = inputs.aliasLine
			}
			if inputs.aliases[key] {
				anchor = key
			}
			if inputs.aliases[value] {
				anchor = value
			}
			fix := "omit"
			detail := fmt.Sprintf("documented default %q at %s", input.value, action.commit)
			if anchor != nil {
				fix = "edit-anchor"
				detail = fmt.Sprintf("edit &%s at line %d by hand to omit this input here and preserve other uses (%s)", anchor.Anchor, anchor.Line, detail)
			}
			findings = append(findings, fmt.Errorf(
				"%s:%d: R35 %s %s %s: %s", path, line, uses.Value, name, fix, detail,
			))
		}
	}
	return findings
}

func matchesDefault(node *yaml.Node, want string) bool {
	node = resolveAlias(node)
	if node.Kind != yaml.ScalarNode {
		return false
	}
	value := node.Value
	switch node.ShortTag() {
	case "!!null":
		value = ""
	case "!!bool":
		value = strings.ToLower(value)
	case "!!int", "!!float":
		value = runnerNumber(value)
	}
	return !strings.Contains(value, "${{") && value == want
}
