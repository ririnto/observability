package main

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

type workflowRevision struct {
	root string
	head string
}

func readWorkflowRevision(path string) *workflowRevision {
	directory := filepath.Dir(path)
	parent := filepath.Dir(directory)
	if filepath.Base(directory) != "workflows" || filepath.Base(parent) != ".github" {
		return &workflowRevision{}
	}
	root := filepath.Dir(parent)
	output, err := gitOutput(root, "rev-parse", "--show-prefix", "--verify", "HEAD^{commit}")
	if err != nil {
		return &workflowRevision{}
	}
	prefix, head, ok := strings.Cut(string(output), "\n")
	if !ok || prefix != "" {
		return &workflowRevision{}
	}
	return &workflowRevision{root: root, head: strings.TrimSpace(head)}
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
	if !filepath.IsLocal(ref) {
		return actionMetadata{}, "local action metadata is unavailable"
	}
	yml := filepath.ToSlash(filepath.Join(ref, "action.yml"))
	yamlPath := filepath.ToSlash(filepath.Join(ref, "action.yaml"))
	if _, err := gitOutput(revision.root, "diff", "--cached", "--quiet", "--no-ext-diff", "--no-textconv", revision.head,
		"--", ":(literal)"+yml, ":(literal)"+yamlPath); err != nil {
		return actionMetadata{}, "local action metadata differs from the workflow revision in the index or cannot be verified"
	}

	var manifest []byte
	var manifestPath string
	for _, path := range []string{yml, yamlPath} {
		pinned, pinnedErr := revision.blob(path)
		worktreePath := filepath.Join(revision.root, filepath.FromSlash(path))
		info, worktreeErr := os.Lstat(worktreePath)
		if pinnedErr == nil || !errors.Is(worktreeErr, os.ErrNotExist) {
			if pinnedErr != nil || worktreeErr != nil || !info.Mode().IsRegular() {
				return actionMetadata{}, "local action metadata differs from the workflow revision in the worktree or cannot be verified"
			}
			current, err := os.ReadFile(worktreePath)
			if err != nil || !bytes.Equal(pinned, current) {
				return actionMetadata{}, "local action metadata differs from the workflow revision in the worktree or cannot be verified"
			}
			if manifestPath == "" {
				manifest, manifestPath = pinned, path
			}
		}
	}
	if manifestPath == "" {
		return actionMetadata{}, "local action metadata is unavailable"
	}
	var document yaml.Node
	if yaml.Unmarshal(manifest, &document) != nil || len(document.Content) == 0 || document.Content[0].Kind != yaml.MappingNode {
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
	return actionMetadata{revision: revision.head + ":" + manifestPath, inputs: inputs}, ""
}
