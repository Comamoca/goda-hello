" End-to-end check: the packaged Vim runs the plugin with no setup.
"
" Unlike test/plugin.vim this script does not put anything on the
" runtimepath and does not set g:goda_hello_bin. The editor wrapper is
" expected to have done both, which is what makes `nix build .#vim` a
" launchable Vim rather than a bare runtimepath directory.
"
" Usage:
"   nix build .#vim
"   ./result/bin/goda-hello-vim -i NONE -N --not-a-term -S test/vim.vim
"
" The check exits non-zero if anything fails, so it can be used from CI.

let s:errors = []

if !exists(':Greet')
  call add(s:errors, ':Greet is not defined')
endif

" goda_hello#bin() must resolve without g:goda_hello_bin being set: the
" binary lives next to the runtimepath directory in the package.
if exists('g:goda_hello_bin')
  call add(s:errors, 'g:goda_hello_bin should not be set by the package')
endif

let s:bin = goda_hello#bin()
if empty(s:bin)
  call add(s:errors, 'goda_hello#bin() found no binary')
elseif !executable(s:bin)
  call add(s:errors, 'goda_hello#bin() returned a non-executable: ' . s:bin)
endif

let s:greet = v:null
let s:cmd = v:null

try
  let s:greet = goda_hello#greet('world')
catch
  call add(s:errors, 'goda_hello#greet() failed: ' . v:exception)
endtry

if type(s:greet) != v:t_string
  call add(s:errors, 'goda_hello#greet() did not return a string: '
        \ . string(s:greet))
elseif s:greet !~# '^hello, world, from vim '
  call add(s:errors, 'unexpected greeting: ' . string(s:greet))
endif

" The greeting has to come from the plugin that was loaded at startup,
" not from a copy sourced by hand.
if !goda#is_running('hello')
  call add(s:errors, 'the "hello" plugin is not running')
endif

try
  redir => s:cmd
  silent Greet
  redir END
catch
  call add(s:errors, ':Greet failed: ' . v:exception)
endtry

if type(s:cmd) != v:t_string
  call add(s:errors, ':Greet produced no output: ' . string(s:cmd))
elseif s:cmd !~# 'hello, world, from vim '
  call add(s:errors, 'unexpected :Greet output: ' . string(s:cmd))
endif

" Stop the child so the editor can exit.
if goda#is_running()
  call goda#stop()
endif

if empty(s:errors)
  let s:lines = [
        \ 'bin=' . s:bin,
        \ 'greet=' . string(s:greet),
        \ 'cmd=' . string(s:cmd),
        \ ]
  call writefile(s:lines, '/dev/stdout')
  if !empty($GODA_HELLO_REPORT)
    call writefile(s:lines, $GODA_HELLO_REPORT)
  endif
  qa!
else
  for s:error in s:errors
    call writefile(['error=' . s:error], '/dev/stdout')
  endfor
  cquit
endif
