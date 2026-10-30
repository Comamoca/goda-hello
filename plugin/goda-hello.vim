" goda-hello: expose the "hello" plugin and :Greet.
"
" The binary is located relative to this file, so the same plugin works from
" a checkout and from the Nix output. See autoload/goda_hello.vim for the
" two layouts and g:goda_hello_bin for an override.

if exists('g:loaded_goda_hello')
  finish
endif
let g:loaded_goda_hello = 1

command! -nargs=0 Greet echo goda_hello#greet('world')

" Start eagerly at VimEnter; goda_hello#greet starts on demand as a fallback.
augroup goda_hello
  autocmd!
  autocmd VimEnter * call goda_hello#start()
augroup END
