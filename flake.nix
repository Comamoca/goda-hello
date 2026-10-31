{
  description = "goda.vim hello world plugin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    # goda.vim is a plain repository, not a flake. It is consumed as a
    # source tree so the editor side (autoload/, doc/) can be installed and
    # the version stays in sync with the Go module.
    goda-vim = {
      url = "github:Shougo/goda.vim/v0.2.1";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      systems,
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks-nix.flakeModule
      ];
      systems = import inputs.systems;

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        let
          lib = pkgs.lib;
          stdenv = pkgs.stdenv;

          # Select a fixed list of files from the checkout. `lib.fileset`
          # has no per-file constructor, so the selection is the union of
          # the named paths: everything else in the checkout, including
          # `.git` and `.direnv`, is left out. A path that moves fails the
          # build instead of silently dropping out of the source tree.
          #
          # The Go module files are optional: a module without dependencies
          # has no go.sum, and `go build` does not need one.
          filesOf = paths: lib.fileset.unions (map lib.fileset.maybeMissing paths);

          # The plugin itself: a single Go binary implementing the "hello" plugin.
          # Pure Go, no cgo, so the result is a static binary.
          #
          # `buildGoModule` vendors the dependencies in a separate derivation
          # and builds against the vendored tree, so the sandbox never needs
          # the network. goda.vim is not fetched from proxy.golang.org but
          # taken from the flake input and wired in with a local `replace`.
          plugin = pkgs.buildGo126Module {
            pname = "goda-hello";
            version = "0.1.0";
            # Only the Go module is needed to build the binary. Restricting
            # the source keeps stray directories in the checkout from
            # breaking `go build`.
            src = lib.fileset.toSource {
              root = ./.;
              fileset = filesOf [
                ./hello/main.go
                ./go.mod
                ./go.sum
              ];
            };
            # The module lives at the root of the source tree, next to
            # flake.nix, so the builder finds go.mod without modRoot.
            vendorHash = "sha256-ZcBle89zEoNo8DjWmXFIanACY9fiaodktS/ukcId9Z0=";
            # `go mod vendor` records the replacement path verbatim in
            # vendor/modules.txt, so the path has to be stable across builds.
            # A fixed absolute path is, while the store path of the input is
            # not: the Go tooling rejects a module whose go.mod and
            # vendor/modules.txt disagree about where it was replaced from,
            # and buildGoModule vendors in one derivation and builds in
            # another, each with its own sandbox. The input is therefore
            # copied to the fixed location below, and the module refers to it
            # by that path. Changing the path invalidates `vendorHash`.
            preBuild = ''
              cp -r --no-preserve=mode ${inputs.goda-vim} /build/goda-vim
              go mod edit -replace=github.com/Shougo/goda.vim=/build/goda-vim
            '';
            # `go install` names the binary after the module, which is
            # the last element of the module path, `hello`. The plugin and
            # the editor side both expect
            # `goda-hello`, so rename it. The rename happens before the
            # install phase copies the binaries into $out.
            postBuild = ''
              mv "$GOPATH/bin/hello" "$GOPATH/bin/goda-hello"
            '';
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              # The jsonl transport answers without an editor, so the built
              # binary can be exercised here. checkPhase runs before
              # installPhase, so the binary is still in $GOPATH/bin.
              echo '{"method":"goda.plugins"}' | "$GOPATH/bin/goda-hello" --transport=jsonl | tr -d '\n' | grep -q '"hello"'
              runHook postCheck
            '';
          };

          # goda.vim's editor side is plain Vim script. It is not in nixpkgs,
          # so it is vendored from the same flake input the Go module pins.
          goda-vim = stdenv.mkDerivation {
            pname = "goda-vim";
            version = "v0.2.1";
            src = inputs.goda-vim;
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/vim/vimfiles
              cp -r autoload doc $out/share/vim/vimfiles/
              runHook postInstall
            '';
          };

          # A drop-in runtimepath directory: goda.vim's autoload/doc, this
          # plugin's Vim script, and the binary. A user adds $out/lib/vim to
          # runtimepath and calls nothing else.
          vim-plugin = stdenv.mkDerivation {
            pname = "goda-hello-vim-plugin";
            version = "0.1.0";
            src = lib.fileset.toSource {
              root = ./.;
              fileset = filesOf [
                ./autoload/goda_hello.vim
                ./plugin/goda-hello.vim
                ./doc/goda-hello.txt
              ];
            };
            dontBuild = true;
            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin $out/lib/vim/autoload $out/lib/vim/doc $out/lib/vim/plugin

              # This plugin's Vim script.
              cp autoload/goda_hello.vim $out/lib/vim/autoload/
              cp plugin/goda-hello.vim $out/lib/vim/plugin/
              cp doc/goda-hello.txt $out/lib/vim/doc/

              # goda.vim's editor side, without overwriting this plugin's files.
              cp ${goda-vim}/share/vim/vimfiles/autoload/goda.vim \
                $out/lib/vim/autoload/goda.vim
              cp ${goda-vim}/share/vim/vimfiles/doc/goda.txt \
                $out/lib/vim/doc/goda.txt

              install -m755 ${plugin}/bin/goda-hello $out/bin/goda-hello

              runHook postInstall
            '';
            passthru = {
              inherit plugin goda-vim;
            };
            meta = with pkgs.lib; {
              description = "goda.vim hello world plugin, ready for runtimepath";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

          # A Vim that is ready to run the plugin: the packaged runtimepath
          # is on `runtimepath` from the start, so `:Greet` works without any
          # further configuration.
          #
          # `pkgs.vim.customize` wraps the editor and points it at a
          # generated vimrc, which is where the runtimepath is added. The
          # plugin directory sits next to `bin/goda-hello`, which is the
          # layout `goda_hello#bin()` looks for, so the binary is found
          # without `g:goda_hello_bin`.
          vim = pkgs.vim.customize {
            name = "goda-hello-vim";
            vimrcConfig.customRC = ''
              set nocompatible
              set runtimepath^=${vim-plugin}/lib/vim
            '';
          };
        in
        {
          # When execute `nix fmt`, formatting your code.
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              gofmt.enable = true;
            };

            settings.formatter = { };
          };

          pre-commit = {
            check.enable = true;
            settings = {
              hooks = {
                treefmt.enable = true;
                ripsecrets.enable = true;
                gitleaks = {
                  enable = true;
                  entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged";
                  language = "system";
                };
              };
            };
          };

          packages = {
            # The default is the editor, because that is what a user of
            # this repository wants to run: `nix build` and then start the
            # plugin. The binary alone is still available as `goda-hello`.
            default = vim;
            goda-hello = plugin;
            goda-vim = goda-vim;
            vim-plugin = vim-plugin;
            vim = vim;
          };

          apps.default = {
            type = "app";
            program = "${vim}/bin/goda-hello-vim";
          };

          checks.plugin = plugin;

          # Drive the packaged plugin the way a user does: a real editor loads
          # it from runtimepath, calls the autoload function and runs :Greet.
          checks.vim-plugin =
            pkgs.runCommand "check-goda-hello-vim-plugin"
              {
                nativeBuildInputs = [
                  pkgs.vim
                  pkgs.gnugrep
                ];
                GODA_HELLO_PLUGIN = vim-plugin;
                GODA_HELLO_REPORT = "vim.report";
              }
              ''
                mkdir -p report
                cd report
                vim -u NONE -i NONE -N --not-a-term \
                  -S ${
                    lib.fileset.toSource {
                      root = ./.;
                      fileset = filesOf [ ./test/plugin.vim ];
                    }
                  }/test/plugin.vim
                grep -qF "hello, world, from vim " vim.report
                cat vim.report
                touch $out
              '';

          checks.vim-plugin-nvim =
            pkgs.runCommand "check-goda-hello-vim-plugin-nvim"
              {
                nativeBuildInputs = [
                  pkgs.neovim
                  pkgs.gnugrep
                ];
                GODA_HELLO_PLUGIN = vim-plugin;
                GODA_HELLO_REPORT = "nvim.report";
              }
              ''
                mkdir -p report
                cd report
                nvim --headless -u NONE -i NONE \
                  -S ${
                    lib.fileset.toSource {
                      root = ./.;
                      fileset = filesOf [ ./test/plugin.vim ];
                    }
                  }/test/plugin.vim
                grep -qF "hello, world, from nvim " nvim.report
                cat nvim.report
                touch $out
              '';

          # Drive the packaged editor itself: the wrapper brings its own
          # vimrc, so the plugin has to be on the runtimepath without any
          # setup by the caller. This is the artifact a user runs.
          checks.vim =
            pkgs.runCommand "check-goda-hello-vim"
              {
                nativeBuildInputs = [
                  pkgs.gnugrep
                ];
                GODA_HELLO_REPORT = "vim.report";
              }
              ''
                mkdir -p report
                cd report
                ${vim}/bin/goda-hello-vim -i NONE -N --not-a-term \
                  -S ${
                    lib.fileset.toSource {
                      root = ./.;
                      fileset = filesOf [ ./test/vim.vim ];
                    }
                  }/test/vim.vim
                grep -qF "hello, world, from vim " vim.report
                cat vim.report
                touch $out
              '';

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nixd
              go
              go_1_26
              gopls
            ];
          };
        };
    };
}
