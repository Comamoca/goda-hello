" End-to-end check: load the plugin from the Nix output and exercise it.
"
" Usage:
"   nix build .#vim-plugin
"   GODA_HELLO_PLUGIN=$(nix build .#vim-plugin --no-link --print-out-paths) \
"     vim -u NONE -i NONE -N --not-a-term -S test/plugin.vim
"
" Without GODA_HELLO_PLUGIN the script falls back to ./result.
"
" The check exits non-zero if anything fails, so it can be used from CI.

set nocompatible

let s:out = empty($GODA_HELLO_PLUGIN)
      \ ? expand('result')
      \ : $GODA_HELLO_PLUGIN

let s:rtp = s:out . '/lib/vim'
let s:errors = []

" Fail fast: a missing package means every later assertion is meaningless.
if !isdirectory(s:rtp)
  call writefile([
        \ 'error=no runtimepath directory at ' . s:rtp
        \ . ' (build with `nix build .#vim-plugin`'
        \ . ' or set $GODA_HELLO_PLUGIN)',
        \ ], '/dev/stdout')
  cquit
endif

execute 'set runtimepath^=' . fnameescape(s:rtp)
filetype plugin indent on
syntax on

" Vim sources plugin/ files at startup, but the runtimepath was changed
" after startup, so source the plugin file explicitly.
runtime! plugin/goda-hello.vim

let s:greet = v:null
let s:cmd = v:null

if !exists(':Greet')
  call add(s:errors, ':Greet is not defined')
endif

" The packaged binary must be discoverable from the plugin directory alone,
" without g:goda_hello_bin, or user configuration would be required.
let s:bin = goda_hello#bin()
if empty(s:bin)
  call add(s:errors, 'goda_hello#bin() found no binary')
elseif !executable(s:bin)
  call add(s:errors, 'goda_hello#bin() returned a non-executable: ' . s:bin)
endif

try
  let s:greet = goda_hello#greet('world')
catch
  call add(s:errors, 'goda_hello#greet() failed: ' . v:exception)
endtry

if type(s:greet) != v:t_string
  call add(s:errors, 'goda_hello#greet() did not return a string: '
        \ . string(s:greet))
elseif s:greet !~# '^hello, world, from '
  call add(s:errors, 'unexpected greeting: ' . string(s:greet))
endif

" The host is reported by the bridge: vim or nvim.
if type(s:greet) == v:t_string && s:greet !~# ', from \(vim\|nvim\) '
  call add(s:errors, 'greeting does not name the host: ' . string(s:greet))
endif

" The plugin must be registered with the bridge.
if !goda#is_running('hello')
  call add(s:errors, 'the "hello" plugin is not running')
endif

if empty(goda#plugins())
  call add(s:errors, 'goda#plugins() is empty')
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
elseif s:cmd !~# 'hello, world, from '
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
