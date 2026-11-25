package main

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

type workflowRevision struct {
	root string
	head string
}

func readWorkflowRevision(path string, data []byte) *workflowRevision {
	directory := filepath.Dir(path)
	parent := filepath.Dir(directory)
	if filepath.Base(directory) != "workflows" || filepath.Base(parent) != ".github" {
		return &workflowRevision{}
	}
	root := filepath.Dir(parent)
	head, err := gitOutput(root, "rev-parse", "--verify", "HEAD^{commit}")
	if err != nil {
		return &workflowRevision{}
	}
	revision := &workflowRevision{root: root, head: strings.TrimSpace(string(head))}
	snapshot, err := revision.blob(".github/workflows/" + filepath.Base(path))
	if err != nil || !bytes.Equal(snapshot, data) {
		return &workflowRevision{}
	}
	return revision
}

func gitOutput(root string, args ...string) ([]byte, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	cmd.Env = append(cmd.Environ(), "GIT_NO_LAZY_FETCH=1")
	return cmd.Output()
}

func (revision *workflowRevision) blob(path string) ([]byte, error) {
	return gitOutput(revision.root, "cat-file", "blob", revision.head+":"+path)
}

func mayReplaceWorkspace(uses *yaml.Node, inputs yamlSource, run *yaml.Node) bool {
	if run != nil {
		return true
	}
	if uses == nil {
		return false
	}
	if uses.Value != "actions/checkout@v6" || (inputs.node != nil && inputs.node.Kind != yaml.MappingNode) {
		return true
	}
	for key, value := range mappingPairs(inputs.node) {
		switch strings.ToLower(resolveAlias(key).Value) {
		case "<<":
			return true
		case "repository", "ref", "path", "github-server-url", "sparse-checkout":
			text, known := runnerScalar(value)
			if !known || strings.TrimSpace(text) != "" {
				return true
			}
		}
	}
	return false
}

func (revision *workflowRevision) localMetadata(ref string) (actionMetadata, string) {
	if revision.head == "" {
		return actionMetadata{}, "the workflow revision is unavailable"
	}
	for _, name := range []string{"action.yml", "action.yaml"} {
		path := filepath.Join(ref, name)
		if filepath.IsLocal(path) {
			data, err := revision.blob(filepath.ToSlash(path))
			if err == nil {
				var document yaml.Node
				if yaml.Unmarshal(data, &document) != nil || len(document.Content) == 0 || document.Content[0].Kind != yaml.MappingNode {
					return actionMetadata{}, "local action metadata is unreadable"
				}
				inputs := make(map[string]inputDefault)
				root := yamlSource{node: document.Content[0]}
				for key, input := range mappingPairs(root.field("inputs").node) {
					node := yamlSource{node: resolveAlias(input)}.field("default").node
					if value, ok := runnerScalar(node); ok && !strings.Contains(value, "${{") {
						inputs[resolveAlias(key).Value] = inputDefault{kind: literalDefault, value: value}
					}
				}
				return actionMetadata{revision: revision.head + ":" + filepath.ToSlash(path), inputs: inputs}, ""
			}
		}
	}
	return actionMetadata{}, "local action metadata is unavailable"
}
