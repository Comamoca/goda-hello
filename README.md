# goda.vim hello, world

The hello world plugin for [goda.vim](https://github.com/Shougo/goda.vim), a
Go based framework that lets Vim and Neovim talk to Go binaries.

The plugin is one Go binary named `hello` that implements a single method,
`greet`. The repository also packages it in two shapes: a ready to use Vim
runtimepath directory, and a Vim that already has that directory on its
runtimepath, so the editor starts with the plugin working and no setup.

```
hello/main.go             the plugin (one method, "greet")
hello/go.mod              the Go module
autoload/goda_hello.vim  goda_hello#bin() / #start() / #greet()
plugin/goda-hello.vim    :Greet, and starts the binary at VimEnter
doc/goda-hello.txt       :help goda-hello
test/plugin.vim          end-to-end check driven by a real editor
test/vim.vim             end-to-end check driven by the packaged Vim
```

## Packages

| Attribute     | Contents                                                       |
| ------------- | -------------------------------------------------------------- |
| `default`     | the editor, same as `vim`                                      |
| `goda-hello`  | just the binary, `$out/bin/goda-hello`                          |
| `vim-plugin`  | binary plus Vim script and goda.vim, `$out/lib/vim`             |
| `vim`         | Vim that loads `vim-plugin` from the start, `bin/goda-hello-vim` |

```sh
nix build .#vim-plugin
```

## Use the packaged Vim

`nix build` produces an editor with the plugin already on its runtimepath.
There is nothing to configure, and `g:goda_hello_bin` does not need to be set:
the binary sits next to the runtimepath directory inside the package.

```sh
nix build
./result/bin/goda-hello-vim
```

Then in the editor:

```vim
:Greet  " echoes: hello, world, from vim (cwd /path/to/where/you/started/vim)
```

`nix run` starts the same editor.

## Use it from another editor

Add the bundled runtimepath directory and call `:Greet`:

```vim
set runtimepath+=/nix/store/...-goda-hello-vim-plugin-0.1.0/lib/vim
```

```vim
:Greet  " echoes: hello, world, from vim (cwd /path/to/where/you/started/vim)
```

The binary is found next to the package's `lib/vim` directory, so nothing else
needs configuring. From a checkout, build first and point at the result:

```vim
let g:goda_hello_bin = expand('<sfile>:p:h:h') . '/result/bin/goda-hello'
```

See `:help goda-hello` for the full reference.

## Without an editor

The `jsonl` transport answers requests over stdin and stdout, so the binary can
be exercised on its own:

```sh
echo '{"method":"goda.plugins"}' | ./result/bin/goda-hello --transport=jsonl
# {"result":{"hello":["greet"]}}
```

## Checks

`nix flake check` runs everything:

- `plugin` builds the binary and asks it for its plugins over `jsonl`.
- `checks.vim-plugin` loads the packaged plugin in Vim, calls
  `goda_hello#greet('world')`, checks that `hello` is registered and that
  `:Greet` echoes the greeting.
- `checks.vim-plugin-nvim` does the same under Neovim.
- `checks.vim` starts the packaged editor with no configuration at all and
  checks the same things, so the artifact a user runs is covered too.

The editor checks run `test/plugin.vim` against the built package, so they
verify the same artifact a user loads rather than the source tree. To run it by
hand against a build:

```sh
GODA_HELLO_PLUGIN=$(nix build .#vim-plugin --no-link --print-out-paths) \
  vim -u NONE -i NONE -N --not-a-term -S test/plugin.vim
```

`checks.vim` runs `test/vim.vim` against the packaged editor. It can be run by
hand the same way:

```sh
nix build
./result/bin/goda-hello-vim -i NONE -N --not-a-term -S test/vim.vim
```

## Notes

- The Nix build has no network access. goda.vim comes from the `goda-vim`
  flake input and is wired into the Go build with a `replace` directive, so
  `hello/go.mod` and the flake input must name the same version.
- Enter the dev shell (`direnv allow` or `nix develop`) for `go` and `nixd`.
- `autoload/goda.vim` and the binary must agree on `sdk.Protocol`. If the
  handshake fails, rebuild the binary against the same goda.vim version.
