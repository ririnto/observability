package main

type defaultKind uint8

const (
	noDefault defaultKind = iota
	literalDefault
	contextDependentDefault
)

type inputDefault struct {
	kind  defaultKind
	value string
}

var actionDefaults = map[string]struct {
	commit string
	inputs map[string]inputDefault
}{
	"actions/checkout@v6": {
		commit: "d23441a48e516b6c34aea4fa41551a30e30af803",
		inputs: map[string]inputDefault{
			"repository":                {kind: contextDependentDefault},
			"ref":                       {kind: contextDependentDefault},
			"token":                     {kind: contextDependentDefault},
			"ssh-key":                   {kind: noDefault},
			"ssh-known-hosts":           {kind: noDefault},
			"ssh-strict":                {kind: literalDefault, value: "true"},
			"ssh-user":                  {kind: literalDefault, value: "git"},
			"persist-credentials":       {kind: literalDefault, value: "true"},
			"path":                      {kind: noDefault},
			"clean":                     {kind: literalDefault, value: "true"},
			"filter":                    {kind: literalDefault, value: ""},
			"sparse-checkout":           {kind: literalDefault, value: ""},
			"sparse-checkout-cone-mode": {kind: literalDefault, value: "true"},
			"fetch-depth":               {kind: literalDefault, value: "1"},
			"fetch-tags":                {kind: literalDefault, value: "false"},
			"show-progress":             {kind: literalDefault, value: "true"},
			"lfs":                       {kind: literalDefault, value: "false"},
			"submodules":                {kind: literalDefault, value: "false"},
			"set-safe-directory":        {kind: literalDefault, value: "true"},
			"github-server-url":         {kind: contextDependentDefault},
			"allow-unsafe-pr-checkout":  {kind: literalDefault, value: "false"},
		},
	},
	"actions/setup-go@v6": {
		commit: "924ae3a1cded613372ab5595356fb5720e22ba16",
		inputs: map[string]inputDefault{
			"go-version":            {kind: noDefault},
			"go-version-file":       {kind: noDefault},
			"check-latest":          {kind: literalDefault, value: "false"},
			"token":                 {kind: contextDependentDefault},
			"cache":                 {kind: literalDefault, value: "true"},
			"cache-dependency-path": {kind: contextDependentDefault},
			"architecture":          {kind: contextDependentDefault},
			"go-download-base-url":  {kind: contextDependentDefault},
		},
	},
	"pnpm/action-setup@v4": {
		commit: "b906affcce14559ad1aafd4ab0e942779e9f58b1",
		inputs: map[string]inputDefault{
			"version":               {kind: contextDependentDefault},
			"dest":                  {kind: contextDependentDefault, value: "~/setup-pnpm"},
			"run_install":           {kind: literalDefault, value: "null"},
			"cache":                 {kind: literalDefault, value: "false"},
			"cache_dependency_path": {kind: literalDefault, value: "pnpm-lock.yaml"},
			"package_json_file":     {kind: literalDefault, value: "package.json"},
			"standalone":            {kind: literalDefault, value: "false"},
		},
	},
	"actions/setup-node@v6": {
		commit: "249970729cb0ef3589644e2896645e5dc5ba9c38",
		inputs: map[string]inputDefault{
			"node-version":          {kind: noDefault},
			"node-version-file":     {kind: noDefault},
			"architecture":          {kind: contextDependentDefault},
			"check-latest":          {kind: literalDefault, value: "false"},
			"registry-url":          {kind: noDefault},
			"scope":                 {kind: contextDependentDefault},
			"token":                 {kind: contextDependentDefault},
			"cache":                 {kind: noDefault},
			"package-manager-cache": {kind: contextDependentDefault, value: "true"},
			"cache-dependency-path": {kind: contextDependentDefault},
			"mirror":                {kind: noDefault},
			"mirror-token":          {kind: noDefault},
		},
	},
	"actions/cache@v5": {
		commit: "caa296126883cff596d87d8935842f9db880ef25",
		inputs: map[string]inputDefault{
			"path":                 {kind: noDefault},
			"key":                  {kind: noDefault},
			"restore-keys":         {kind: noDefault},
			"upload-chunk-size":    {kind: noDefault},
			"enablecrossosarchive": {kind: literalDefault, value: "false"},
			"fail-on-cache-miss":   {kind: literalDefault, value: "false"},
			"lookup-only":          {kind: literalDefault, value: "false"},
			"save-always":          {kind: literalDefault, value: "false"},
		},
	},
}
