package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/prometheus/prometheus/promql/parser"
	"go.yaml.in/yaml/v3"
)

func main() {
	stripComments := flag.Bool("strip-promql-comments", false, "strip comments from rule expressions")
	flag.Parse()
	if flag.NArg() == 0 {
		fmt.Fprintln(os.Stderr, "Usage: formatyaml [-strip-promql-comments] FILE.yaml [FILE.yaml ...]")
		os.Exit(2)
	}
	for _, path := range flag.Args() {
		if err := format(path, *stripComments); err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", path, err)
			os.Exit(1)
		}
	}
}

func format(path string, stripComments bool) error {
	input, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var document map[string]any
	if err := yaml.Unmarshal(input, &document); err != nil {
		return err
	}
	if stripComments {
		for _, group := range mappings(document["groups"]) {
			for _, rule := range mappings(group["rules"]) {
				if err := stripExpressionComments(rule); err != nil {
					return err
				}
				for _, query := range mappings(rule["data"]) {
					if model, ok := query["model"].(map[string]any); ok && query["datasourceUid"] == "prometheus" {
						if err := stripExpressionComments(model); err != nil {
							return err
						}
					}
				}
			}
		}
	}
	output, err := yaml.Marshal(document)
	if err != nil {
		return err
	}
	return os.WriteFile(path, output, 0o644)
}

func mappings(value any) []map[string]any {
	items, _ := value.([]any)
	mappings := make([]map[string]any, 0, len(items))
	for _, item := range items {
		if mapping, ok := item.(map[string]any); ok {
			mappings = append(mappings, mapping)
		}
	}
	return mappings
}

func stripExpressionComments(model map[string]any) error {
	expr, ok := model["expr"].(string)
	if !ok || !strings.Contains(expr, "#") {
		return nil
	}
	lexer := parser.Lex(expr)
	var stripped strings.Builder
	from := 0
	for {
		var token parser.Item
		lexer.NextItem(&token)
		switch token.Typ {
		case parser.EOF:
			if from > 0 {
				stripped.WriteString(expr[from:])
				model["expr"] = stripped.String()
			}
			return nil
		case parser.ERROR:
			return fmt.Errorf("lex PromQL at byte %d: %s", token.Pos, token.Val)
		case parser.COMMENT:
			start := int(token.Pos)
			end := start + len(token.Val)
			lineStart := strings.LastIndexAny(expr[:start], "\r\n") + 1
			start = lineStart + len(strings.TrimRight(expr[lineStart:start], " \t"))
			if start == lineStart {
				if end < len(expr) && expr[end] == '\r' {
					end++
				}
				if end < len(expr) && expr[end] == '\n' {
					end++
				}
			}
			stripped.WriteString(expr[from:start])
			from = end
		}
	}
}
