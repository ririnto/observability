package main

import (
	"fmt"
	"maps"
	"slices"
	"strings"

	"go.yaml.in/yaml/v3"
)

type defaultKind uint8

const (
	noDefault defaultKind = iota
	literalDefault
	contextDependentDefault
)

type inputDefault struct {
	kind      defaultKind
	value     string
	condition string
}

type actionMetadata struct {
	revision string
	inputs   map[string]inputDefault
}

func (action actionMetadata) input(name string) inputDefault {
	for key, value := range action.inputs {
		if strings.EqualFold(key, name) {
			return value
		}
	}
	return inputDefault{}
}

func fixed(raw string) inputDefault {
	var document yaml.Node
	if err := yaml.Unmarshal([]byte(raw), &document); err != nil {
		panic(err)
	}
	value, ok := runnerScalar(document.Content[0])
	if !ok {
		panic("unsupported approved default: " + raw)
	}
	return inputDefault{kind: literalDefault, value: value}
}

var actionDefaults = map[string]actionMetadata{
	"actions/checkout@v6": {
		revision: "d23441a48e516b6c34aea4fa41551a30e30af803",
		inputs: map[string]inputDefault{
			"repository":                {kind: contextDependentDefault, condition: "Uses the repository that triggered the workflow."},
			"ref":                       {kind: contextDependentDefault, condition: "Uses the event ref or SHA for the triggering repository, or the default branch for another repository."},
			"token":                     {kind: contextDependentDefault, condition: "Uses the workflow GitHub token."},
			"ssh-key":                   {kind: noDefault},
			"ssh-known-hosts":           {kind: noDefault},
			"ssh-strict":                fixed("true"),
			"ssh-user":                  fixed("git"),
			"persist-credentials":       fixed("true"),
			"path":                      {kind: noDefault},
			"clean":                     fixed("true"),
			"filter":                    fixed("null"),
			"sparse-checkout":           fixed("null"),
			"sparse-checkout-cone-mode": fixed("true"),
			"fetch-depth":               fixed("1"),
			"fetch-tags":                fixed("false"),
			"show-progress":             fixed("true"),
			"lfs":                       fixed("false"),
			"submodules":                fixed("false"),
			"set-safe-directory":        fixed("true"),
			"github-server-url":         {kind: contextDependentDefault, condition: "Uses the server URL from the runner environment."},
			"allow-unsafe-pr-checkout":  fixed("false"),
		},
	},
	"actions/setup-go@v6": {
		revision: "924ae3a1cded613372ab5595356fb5720e22ba16",
		inputs: map[string]inputDefault{
			"go-version":            {kind: noDefault},
			"go-version-file":       {kind: noDefault},
			"check-latest":          fixed("false"),
			"token":                 {kind: contextDependentDefault, condition: "Uses the workflow GitHub token on github.com and an empty string on GitHub Enterprise Server."},
			"cache":                 fixed("true"),
			"cache-dependency-path": {kind: contextDependentDefault, condition: "Uses go.sum in the workspace when caching is enabled and no dependency path is supplied."},
			"architecture":          {kind: contextDependentDefault, condition: "Uses the runner architecture."},
			"go-download-base-url":  {kind: contextDependentDefault, condition: "Uses GO_DOWNLOAD_BASE_URL when set, or the standard Go download URL."},
		},
	},
	"pnpm/action-setup@v4": {
		revision: "b906affcce14559ad1aafd4ab0e942779e9f58b1",
		inputs: map[string]inputDefault{
			"version":               {kind: contextDependentDefault, condition: "Reads packageManager from the manifest selected by package_json_file when no version is supplied."},
			"dest":                  fixed("~/setup-pnpm"),
			"run_install":           fixed("'null'"),
			"cache":                 fixed("false"),
			"cache_dependency_path": fixed("pnpm-lock.yaml"),
			"package_json_file":     fixed("package.json"),
			"standalone":            fixed("false"),
		},
	},
	"actions/setup-node@v6": {
		revision: "249970729cb0ef3589644e2896645e5dc5ba9c38",
		inputs: map[string]inputDefault{
			"node-version":          {kind: noDefault},
			"node-version-file":     {kind: noDefault},
			"architecture":          {kind: contextDependentDefault, condition: "Uses the runner architecture."},
			"check-latest":          fixed("false"),
			"registry-url":          {kind: noDefault},
			"scope":                 {kind: contextDependentDefault, condition: "Uses the repository owner as the scope for the GitHub Packages registry."},
			"token":                 {kind: contextDependentDefault, condition: "Uses the workflow GitHub token on github.com and an empty string on GitHub Enterprise Server."},
			"cache":                 {kind: noDefault},
			"package-manager-cache": {kind: contextDependentDefault, condition: "Enables automatic npm caching when package.json declares npm and no cache input is supplied."},
			"cache-dependency-path": {kind: contextDependentDefault, condition: "Uses the lockfile for the selected package manager in the workspace when no path is supplied."},
			"mirror":                {kind: noDefault},
			"mirror-token":          {kind: noDefault},
		},
	},
	"actions/cache@v5": {
		revision: "caa296126883cff596d87d8935842f9db880ef25",
		inputs: map[string]inputDefault{
			"path":                 {kind: noDefault},
			"key":                  {kind: noDefault},
			"restore-keys":         {kind: noDefault},
			"upload-chunk-size":    {kind: noDefault},
			"enableCrossOsArchive": fixed("false"),
			"fail-on-cache-miss":   fixed("false"),
			"lookup-only":          fixed("false"),
			"save-always":          fixed("false"),
		},
	},
}

func printMetadata() {
	for _, ref := range slices.Sorted(maps.Keys(actionDefaults)) {
		action := actionDefaults[ref]
		for _, name := range slices.Sorted(maps.Keys(action.inputs)) {
			input := action.inputs[name]
			fmt.Printf("%s %s %s ", ref, action.revision, name)
			switch input.kind {
			case contextDependentDefault:
				fmt.Printf("context-dependent: %s\n", input.condition)
			case literalDefault:
				fmt.Printf("literal: %q\n", input.value)
			case noDefault:
				fmt.Println("no default")
			}
		}
	}
}
