syntax on
filetype plugin indent off

set fileformat=unix
set modeline
set nowrap

set tabstop=3

set listchars=tab:▸\ ,trail:·
set list

if &diff
  colorscheme murphy
endif
