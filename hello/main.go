package main

import (
	"context"
	"fmt"

	"github.com/Shougo/goda.vim/host"
	"github.com/Shougo/goda.vim/sdk"
)

type hello struct{}

func (hello) Name() string { return "hello" }

func (hello) Handlers() map[string]sdk.Handler {
	return map[string]sdk.Handler{
		"greet": func(ctx context.Context, h sdk.Host, params []any) (any, error) {
			cwd, err := h.Call(ctx, "getcwd")
			if err != nil {
				return nil, err
			}
			return fmt.Sprintf("hello, %v, from %s (cwd %v)", params[0], h.Meta().Host, cwd), nil
		},
	}
}

func main() { host.Main(hello{}) }
