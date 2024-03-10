set number
set title
set laststatus=2
set wildmenu
syntax on

set incsearch
set hlsearch
set smartindent

inoremap <silent> jk <ESC>

if &term =~ '^xterm'
  " enter vim
  autocmd VimEnter * silent !echo -ne "\e[3 q"
  " oherwise
  let &t_EI .= "\<Esc>[3 q"
  " insert mode
  let &t_SI .= "\<Esc>[5 q"
  " 1 or 0 -> blinking block
  " 2 -> solid block
  " 3 -> blinking underscore
  " 4 -> solid underscore
  " Recent versions of xterm (282 or above) also support
  " 5 -> blinking vertical bar
  " 6 -> solid vertical bar
  " leave vim
  autocmd VimLeave * silent !echo -ne "\e[5 q"
endif

"vim-jetpack automatic installation
let s:jetpackfile = expand('<sfile>:p:h') .. '/pack/jetpack/opt/vim-jetpack/plugin/jetpack.vim'
let s:jetpackurl = "https://raw.githubusercontent.com/tani/vim-jetpack/master/plugin/jetpack.vim"
if !filereadable(s:jetpackfile)
  call system(printf('curl -fsSLo %s --create-dirs %s', s:jetpackfile, s:jetpackurl))
endif

" vim-jetpack install
packadd vim-jetpack
call jetpack#begin()
  Jetpack 'tani/vim-jetpack', {'opt': 1} "bootstrap
  Jetpack 'doums/darcula'
call jetpack#end()

" vim-jetpack plugin install
for name in jetpack#names()
  if !jetpack#tap(name)
    call jetpack#sync()
    break
  endif
endfor

"colorscheme darcula
