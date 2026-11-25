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
		fmt.Fprintln(os.Stderr, "Usage: workflowcheck WORKFLOWS_DIRECTORY | --list-metadata")
		os.Exit(2)
	}
	if os.Args[1] == "--list-metadata" {
		printMetadata()
		return
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

type actionStep struct {
	ref      string
	inputs   yamlSource
	metadata actionMetadata
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

	root := yamlSource{aliases: referencedAnchors(&document)}.child(document.Content[0])
	jobs := root.field("jobs")
	var actions []actionStep
	mappingUsers := make(map[*yaml.Node][]actionStep)
	var revision *workflowRevision
	for key, job := range mappingPairs(jobs.node) {
		steps := jobs.child(key).child(job).field("steps")
		workspaceMayDiffer := false
		if steps.node != nil && steps.node.Kind == yaml.SequenceNode {
			for _, node := range steps.node.Content {
				step := steps.child(node)
				uses, inputs := step.field("uses"), step.field("with")
				if uses.node != nil {
					ref := uses.node.Value
					metadata := actionDefaults[ref]
					if strings.HasPrefix(ref, "./") {
						var reason string
						if workspaceMayDiffer {
							reason = "an earlier step may replace the workspace"
						} else {
							if revision == nil {
								revision = readWorkflowRevision(path, data)
							}
							metadata, reason = revision.localMetadata(ref)
						}
						if reason != "" {
							if _, err := fmt.Fprintf(os.Stdout, "%s:%d: %s left to review: %s\n", path, uses.line(), ref, reason); err != nil {
								return fmt.Errorf("write local action review report: %w", err)
							}
						}
					}
					if inputs.node != nil && inputs.node.Kind == yaml.MappingNode {
						inputs.anchors = slices.Concat(inputs.anchors, uses.anchors)
						action := actionStep{ref: ref, inputs: inputs, metadata: metadata}
						actions = append(actions, action)
						mappingUsers[inputs.node] = append(mappingUsers[inputs.node], action)
					}
				}
				workspaceMayDiffer = workspaceMayDiffer || mayReplaceWorkspace(uses.node, inputs, step.field("run").node)
			}
		}
	}
	var findings []error
	for _, action := range actions {
		findings = append(findings, checkInputs(path, action, mappingUsers[action.inputs.node])...)
	}
	return errors.Join(findings...)
}

func (source yamlSource) line() int {
	if source.collection != nil {
		return source.collection.Line
	}
	return source.origin.Line
}

func checkInputs(path string, action actionStep, users []actionStep) []error {
	var findings []error
	for key, value := range mappingPairs(action.inputs.node) {
		name := resolveAlias(key).Value
		input := action.metadata.input(name)
		actual, known := runnerScalar(value)
		if known && !strings.Contains(actual, "${{") && input.kind == literalDefault && actual == input.value {
			source := action.inputs.child(key).child(value)
			line := key.Line
			var otherRefs []string
			sharedDefault := true
			for _, user := range users {
				defaultForUser := user.metadata.input(name)
				sharedDefault = sharedDefault && defaultForUser.kind == literalDefault && defaultForUser.value == actual
				if !slices.Contains(otherRefs, user.ref) {
					otherRefs = append(otherRefs, user.ref)
				}
			}

			advice, fix := "omit-input", "omit this input"
			switch {
			case value.Kind == yaml.AliasNode:
				line = value.Line
				if source.collection != nil {
					line = source.collection.Line
				}
				advice, fix = "hand-edit", "hand edit this value alias and preserve its anchor and every use"
			case source.collection != nil:
				line = source.collection.Line
				advice, fix = "detach-and-omit", "detach this step's mapping and omit this input from the detached mapping. Preserve the shared definition"
				if source.collection.Alias != action.inputs.node {
					fix = "expand the enclosing alias, then " + fix
				}
			case !sharedDefault:
				advice, fix = "shared-definition", "review this shared definition by hand"
			case len(source.anchors) != 0:
				advice, fix = "hand-edit", "hand edit this input and preserve the referenced anchors"
			default:
				for _, node := range []*yaml.Node{key, value} {
					if node.Anchor != "" {
						fix += fmt.Sprintf(" together with its unused anchor &%s", node.Anchor)
					}
				}
			}
			if !sharedDefault {
				fix += ". Actions using this mapping: " + strings.Join(otherRefs, ", ")
			}
			seenAnchors := make(map[*yaml.Node]bool)
			for _, anchor := range source.anchors {
				if !seenAnchors[anchor] {
					fix += fmt.Sprintf(". Anchor &%s defined at %s:%d", anchor.Anchor, path, anchor.Line)
					for _, alias := range source.aliases[anchor] {
						fix += fmt.Sprintf(", alias %s:%d", path, alias.Line)
					}
					seenAnchors[anchor] = true
				}
			}
			findings = append(findings, fmt.Errorf(
				"%s:%d: R35 %s %s [%s]: %s (documented default %q at %s)", path, line, action.ref, name, advice, fix, input.value, action.metadata.revision,
			))
		}
	}
	return findings
}
