" goda-hello#greet: convenience wrapper around the "greet" method.
"
" Using it instead of goda#request('hello', 'greet', ...) starts the binary
" on demand, so the command works even if VimEnter already passed or the
" binary was built after the editor started.

" This file is <root>/autoload/goda_hello.vim, so <root> is two levels up.
let s:root = expand('<sfile>:p:h:h')

function! s:path_join(...) abort
  return join(filter(copy(a:000), '!empty(v:val)'), '/')
endfunction

" Locate the binary. The layouts are:
"
"   checkout   <root>/bin/goda-hello, <root>/result/bin/goda-hello
"   nix        <root>/../../bin/goda-hello, that is $out/bin next to
"              the $out/lib/vim runtimepath directory
"
" g:goda_hello_bin overrides the search.
function! goda_hello#bin() abort
  if exists('g:goda_hello_bin') && !empty(g:goda_hello_bin)
    return g:goda_hello_bin
  endif

  for l:cand in [
        \ s:path_join(s:root, 'bin', 'goda-hello'),
        \ s:path_join(s:root, 'result', 'bin', 'goda-hello'),
        \ s:path_join(s:root, '..', '..', 'bin', 'goda-hello'),
        \ ]
    if executable(l:cand)
      return fnamemodify(l:cand, ':p')
    endif
  endfor

  return ''
endfunction

" Start the binary and return its path, or '' if it is missing.
function! goda_hello#start() abort
  let l:bin = goda_hello#bin()
  if empty(l:bin)
    return ''
  endif
  call goda#start(l:bin)
  return l:bin
endfunction

function! goda_hello#greet(...) abort
  if !goda#is_running()
    if empty(goda_hello#start())
      throw 'goda-hello: binary not found. Set g:goda_hello_bin or run `nix build`.'
    endif
  endif
  return call('goda#request', ['hello', 'greet'] + a:000)
endfunction
