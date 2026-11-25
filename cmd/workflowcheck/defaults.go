package main

type inputDefault struct {
	value            string
	contextDependent bool
}

var actionDefaults = map[string]struct {
	commit string
	inputs map[string]inputDefault
}{
	"actions/checkout@v6": {
		commit: "d23441a48e516b6c34aea4fa41551a30e30af803",
		inputs: map[string]inputDefault{
			"repository":                {contextDependent: true},
			"ref":                       {contextDependent: true},
			"token":                     {contextDependent: true},
			"ssh-strict":                {value: "true"},
			"ssh-user":                  {value: "git"},
			"persist-credentials":       {value: "true"},
			"clean":                     {value: "true"},
			"filter":                    {value: ""},
			"sparse-checkout":           {value: ""},
			"sparse-checkout-cone-mode": {value: "true"},
			"fetch-depth":               {value: "1"},
			"fetch-tags":                {value: "false"},
			"show-progress":             {value: "true"},
			"lfs":                       {value: "false"},
			"submodules":                {value: "false"},
			"set-safe-directory":        {value: "true"},
			"github-server-url":         {contextDependent: true},
			"allow-unsafe-pr-checkout":  {value: "false"},
		},
	},
	"actions/setup-go@v6": {
		commit: "924ae3a1cded613372ab5595356fb5720e22ba16",
		inputs: map[string]inputDefault{
			"check-latest":         {value: "false"},
			"token":                {contextDependent: true},
			"cache":                {value: "true"},
			"architecture":         {contextDependent: true},
			"go-download-base-url": {contextDependent: true},
		},
	},
	"pnpm/action-setup@v4": {
		commit: "b906affcce14559ad1aafd4ab0e942779e9f58b1",
		inputs: map[string]inputDefault{
			"dest":                  {value: "~/setup-pnpm", contextDependent: true},
			"run_install":           {value: "null"},
			"cache":                 {value: "false"},
			"cache_dependency_path": {value: "pnpm-lock.yaml"},
			"package_json_file":     {value: "package.json"},
			"standalone":            {value: "false"},
		},
	},
	"actions/setup-node@v6": {
		commit: "249970729cb0ef3589644e2896645e5dc5ba9c38",
		inputs: map[string]inputDefault{
			"architecture":          {contextDependent: true},
			"check-latest":          {value: "false"},
			"token":                 {contextDependent: true},
			"package-manager-cache": {value: "true", contextDependent: true},
		},
	},
	"actions/cache@v5": {
		commit: "caa296126883cff596d87d8935842f9db880ef25",
		inputs: map[string]inputDefault{
			"enablecrossosarchive": {value: "false"},
			"fail-on-cache-miss":   {value: "false"},
			"lookup-only":          {value: "false"},
			"save-always":          {value: "false"},
		},
	},
}
