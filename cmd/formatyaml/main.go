package main

import (
	"fmt"
	"os"

	"go.yaml.in/yaml/v3"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "Usage: formatyaml FILE.yaml [FILE.yaml ...]")
		os.Exit(2)
	}
	for _, path := range os.Args[1:] {
		if err := format(path); err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", path, err)
			os.Exit(1)
		}
	}
}

func format(path string) error {
	input, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var document map[string]any
	if err := yaml.Unmarshal(input, &document); err != nil {
		return err
	}
	output, err := yaml.Marshal(document)
	if err != nil {
		return err
	}
	return os.WriteFile(path, output, 0o644)
}
