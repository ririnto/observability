package main

import (
	"errors"
	"iter"
	"math"
	"regexp"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

type yamlSource struct {
	node      *yaml.Node
	aliases   map[*yaml.Node]bool
	anchor    *yaml.Node
	aliasLine int
}

func (source yamlSource) child(node *yaml.Node) yamlSource {
	if node.Kind == yaml.AliasNode && source.aliasLine == 0 {
		source.aliasLine = node.Line
	}
	source.node = resolveAlias(node)
	if source.aliases[source.node] {
		source.anchor = source.node
	}
	return source
}

func (source yamlSource) field(name string) yamlSource {
	for key, child := range mappingPairs(source.node) {
		if strings.EqualFold(resolveAlias(key).Value, name) {
			return source.child(child)
		}
	}
	return yamlSource{}
}

func mappingPairs(node *yaml.Node) iter.Seq2[*yaml.Node, *yaml.Node] {
	return func(yield func(*yaml.Node, *yaml.Node) bool) {
		if node != nil && node.Kind == yaml.MappingNode {
			for i := 0; i < len(node.Content); i += 2 {
				if !yield(node.Content[i], node.Content[i+1]) {
					return
				}
			}
		}
	}
}

func resolveAlias(node *yaml.Node) *yaml.Node {
	if node.Kind == yaml.AliasNode {
		return node.Alias
	}
	return node
}

func referencedAnchors(document *yaml.Node) map[*yaml.Node]bool {
	anchors := make(map[*yaml.Node]bool)
	stack := []*yaml.Node{document}
	for len(stack) > 0 {
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if node.Kind == yaml.AliasNode {
			anchors[node.Alias] = true
		}
		stack = append(stack, node.Content...)
	}
	return anchors
}

var decimalNumber = regexp.MustCompile(`^[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?$`)

func runnerNumber(value string) string {
	var number float64
	switch {
	case strings.HasPrefix(value, "0x"), strings.HasPrefix(value, "0o"):
		base := 16
		if value[1] == 'o' {
			base = 8
		}
		integer, err := strconv.ParseUint(value[2:], base, 32)
		if err != nil {
			return value
		}
		number = float64(int32(integer))
	case decimalNumber.MatchString(value):
		parsed, err := strconv.ParseFloat(value, 64)
		if err != nil && !errors.Is(err, strconv.ErrRange) {
			return value
		}
		number = parsed
	default:
		switch strings.ToLower(value) {
		case ".inf", "+.inf":
			return "Infinity"
		case "-.inf":
			return "-Infinity"
		case ".nan":
			return "NaN"
		}
		return value
	}
	if math.IsInf(number, 1) {
		return "Infinity"
	}
	if math.IsInf(number, -1) {
		return "-Infinity"
	}
	// GitHub's NumberToken formats doubles with invariant G15.
	return strconv.FormatFloat(number, 'G', 15, 64)
}
