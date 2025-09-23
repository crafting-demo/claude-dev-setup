//go:build mcp_subagents
// +build mcp_subagents

package mcp

import (
	"github.com/flosch/pongo2/v6"
)

func Render(template string, params map[string]any) (string, error) {
	tpl, err := pongo2.FromString(template)
	if err != nil {
		return "", err
	}
	ctx := pongo2.Context{}
	for k, v := range params {
		ctx[k] = v
	}
	return tpl.Execute(ctx)
}
