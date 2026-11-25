package main

import (
	"errors"
	"iter"
	"math"
	"math/big"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

type yamlSource struct {
	node       *yaml.Node
	origin     *yaml.Node
	aliases    map[*yaml.Node][]*yaml.Node
	anchors    []*yaml.Node
	collection *yaml.Node
}

func (source yamlSource) child(node *yaml.Node) yamlSource {
	source.node = resolveAlias(node)
	source.origin = node
	if node.Kind == yaml.AliasNode && source.collection == nil &&
		(source.node.Kind == yaml.MappingNode || source.node.Kind == yaml.SequenceNode) {
		source.collection = node
	}
	if len(source.aliases[source.node]) != 0 {
		source.anchors = slices.Concat(source.anchors, []*yaml.Node{source.node})
	}
	return source
}

func (source yamlSource) field(name string) yamlSource {
	for key, child := range mappingPairs(source.node) {
		if strings.EqualFold(resolveAlias(key).Value, name) {
			return source.child(key).child(child)
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
	if node != nil && node.Kind == yaml.AliasNode {
		return node.Alias
	}
	return node
}

func referencedAnchors(document *yaml.Node) map[*yaml.Node][]*yaml.Node {
	anchors := make(map[*yaml.Node][]*yaml.Node)
	stack := []*yaml.Node{document}
	for len(stack) > 0 {
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if node.Kind == yaml.AliasNode {
			anchors[node.Alias] = append(anchors[node.Alias], node)
		}
		for i := len(node.Content) - 1; i >= 0; i-- {
			stack = append(stack, node.Content[i])
		}
	}
	return anchors
}

var (
	decimalInteger = regexp.MustCompile(`^[-+]?[0-9]+$`)
	decimalNumber  = regexp.MustCompile(`^[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?$`)
	hexInteger     = regexp.MustCompile(`^0x[0-9a-fA-F]+$`)
	octalInteger   = regexp.MustCompile(`^0o[0-7]+$`)
)

func runnerScalar(node *yaml.Node) (string, bool) {
	node = resolveAlias(node)
	if node == nil || node.Kind != yaml.ScalarNode {
		return "", false
	}
	value, tag := node.Value, node.ShortTag()
	style := node.Style &^ yaml.TaggedStyle
	explicit := node.Style&yaml.TaggedStyle != 0
	if (explicit && tag == "!!str") || (!explicit && style != 0) {
		return value, true
	}
	if style != 0 {
		return "", false
	}
	if !explicit {
		tag = ""
	}
	switch value {
	case "", "~", "null", "Null", "NULL":
		return "", tag == "" || tag == "!!null"
	case "true", "True", "TRUE", "false", "False", "FALSE":
		return strings.ToLower(value), tag == "" || tag == "!!bool"
	}
	switch tag {
	case "", "!!int", "!!float":
		return runnerNumberOrString(value, tag)
	}
	return "", false
}

func runnerNumberOrString(value, tag string) (string, bool) {
	digits, base := value, 0
	if tag != "!!float" {
		switch {
		case decimalInteger.MatchString(value):
			base = 10
		case hexInteger.MatchString(value):
			digits, base = value[2:], 16
		case octalInteger.MatchString(value):
			digits, base = value[2:], 8
		}
	}
	if base != 0 {
		integer, ok := new(big.Int).SetString(digits, base)
		if !ok {
			return "", false
		}
		return integer.String(), true
	}
	if tag != "!!int" && decimalNumber.MatchString(value) {
		number, err := strconv.ParseFloat(value, 64)
		if err != nil && !errors.Is(err, strconv.ErrRange) {
			return "", false
		}
		return formatRunnerNumber(number), true
	}
	if tag != "!!int" {
		switch value {
		case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF":
			return "Infinity", true
		case "-.inf", "-.Inf", "-.INF":
			return "-Infinity", true
		case ".nan", ".NaN", ".NAN":
			return "NaN", true
		}
	}
	return value, tag == ""
}

// GitHub's NumberToken formats doubles with invariant G15.
func formatRunnerNumber(number float64) string {
	switch {
	case math.IsInf(number, 1):
		return "Infinity"
	case math.IsInf(number, -1):
		return "-Infinity"
	default:
		return strconv.FormatFloat(number, 'G', 15, 64)
	}
}
