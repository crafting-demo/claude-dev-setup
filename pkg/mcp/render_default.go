package mcp

// Default renderer: passthrough. Overridden by Jinja renderer when built with tags.
func Render(template string, params map[string]any) (string, error) {
	return template, nil
}
