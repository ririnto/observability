// Command workflowcheck checks workflow inputs against approved action metadata without network access.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
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
	type actionStep struct {
		ref    string
		inputs yamlSource
	}
	var stepsToCheck []actionStep
	mappingUsers := make(map[*yaml.Node][]string)
	for _, job := range mappingPairs(jobs.node) {
		steps := jobs.child(job).field("steps")
		if steps.node != nil && steps.node.Kind == yaml.SequenceNode {
			for _, node := range steps.node.Content {
				step := steps.child(node)
				uses, inputs := step.field("uses").node, step.field("with")
				if uses != nil && inputs.node != nil && inputs.node.Kind == yaml.MappingNode {
					stepsToCheck = append(stepsToCheck, actionStep{ref: uses.Value, inputs: inputs})
					if len(inputs.aliases[inputs.node]) != 0 && !slices.Contains(mappingUsers[inputs.node], uses.Value) {
						mappingUsers[inputs.node] = append(mappingUsers[inputs.node], uses.Value)
					}
				}
			}
		}
	}
	var findings []error
	for _, step := range stepsToCheck {
		findings = append(findings, checkInputs(path, step.ref, step.inputs, mappingUsers[step.inputs.node])...)
	}
	return errors.Join(findings...)
}

func checkInputs(path, ref string, inputs yamlSource, mappingUsers []string) []error {
	action, ok := actionDefaults[ref]
	if !ok {
		return nil
	}

	var findings []error
	for key, value := range mappingPairs(inputs.node) {
		name := resolveAlias(key).Value
		input, ok := action.inputs[strings.ToLower(name)]
		if ok && input.kind == literalDefault && matchesDefault(value, input.value) {
			line := key.Line
			fix := "omit this input"
			var references []string
			anchors := slices.Clone(inputs.anchors)
			for _, node := range []*yaml.Node{key, value} {
				anchor := resolveAlias(node)
				if len(inputs.aliases[anchor]) != 0 && !slices.Contains(anchors, anchor) {
					anchors = append(anchors, anchor)
				}
			}
			switch {
			case inputs.alias != nil:
				line = inputs.alias.Line
				fix = "detach this step's mapping at the alias use and omit this input there. Leave the shared definition intact"
			case value.Kind == yaml.AliasNode:
				line = value.Line
				fix = "review this input alias by hand and preserve its anchor and other references"
			case len(anchors) != 0:
				fix = "review this anchored input by hand and preserve the shared definition and its aliases"
			default:
				for _, node := range []*yaml.Node{key, value} {
					if node.Anchor != "" {
						fix += fmt.Sprintf(" together with its unused anchor &%s", node.Anchor)
					}
				}
			}
			for _, anchor := range anchors {
				reference := fmt.Sprintf("&%s (%s:%d)", anchor.Anchor, path, anchor.Line)
				for _, alias := range inputs.aliases[anchor] {
					reference += fmt.Sprintf(", alias %s:%d", path, alias.Line)
				}
				references = append(references, reference)
			}
			if len(references) != 0 {
				fix += ". Shared definitions: " + strings.Join(references, " | ")
			}
			if len(mappingUsers) > 1 {
				fix += ". Actions using this mapping: " + strings.Join(mappingUsers, ", ")
			}
			findings = append(findings, fmt.Errorf(
				"%s:%d: R35 %s %s: %s (documented default %q at %s)", path, line, ref, name, fix, input.value, action.commit,
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
