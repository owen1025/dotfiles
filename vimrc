" ################## Vim Plugin management #######################
" 
" ####################### Vundle start #######################
set nocompatible              " be iMproved, required
filetype off                  " required

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

Plugin 'VundleVim/Vundle.vim'
Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'
Plugin 'jistr/vim-nerdtree-tabs'
Plugin 'Xuyuanp/nerdtree-git-plugin'
Plugin 'Yggdroot/indentLine'
Plugin 'scrooloose/syntastic'
Plugin 'tpope/vim-fugitive'
Plugin 'airblade/vim-gitgutter'
Plugin 'jiangmiao/auto-pairs'
Plugin 'leafgarland/typescript-vim'
Plugin 'hashivim/vim-terraform'
Plugin 'easymotion/vim-easymotion'
Plugin 'tpope/vim-surround'

call vundle#end()            " required
filetype plugin indent on" required
" ####################### Vundle stop #######################

" ####################### vim-plug start #######################
call plug#begin('~/.vim/plugged')

Plug 'preservim/nerdtree'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --bin' }
Plug 'junegunn/fzf.vim'
Plug 'ryanoasis/vim-devicons'
Plug 'scrooloose/nerdcommenter'
Plug 'kaicataldo/material.vim'
Plug 'cespare/vim-toml'
Plug 'chr4/nginx.vim'
Plug 'moby/moby' , {'rtp': '/contrib/syntax/vim/'}
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'mg979/vim-visual-multi', {'branch': 'master'}
Plug 'pearofducks/ansible-vim'
Plug 'pangloss/vim-javascript'
Plug 'APZelos/blamer.nvim'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
Plug 'nvim-lua/plenary.nvim'
Plug 'sindrets/diffview.nvim'
Plug 't9md/vim-choosewin'
Plug 'sheerun/vim-polyglot'
Plug 'antoinemadec/coc-fzf'
Plug 'brooth/far.vim'

" Initialize plugin system
call plug#end()
" ####################### vim-plug stop ####################### 

" ####################### Owen config start #######################

" General setting
set number
let mapleader=","
set encoding=UTF-8
set mouse=a
set cursorline
set nobackup
set nowritebackup
set noswapfile
set listchars=tab:\|\
set list
set updatetime=300
set autoread
au CursorHold * checktime
set splitright
set autoindent
set shiftwidth=4
set softtabstop=4 
set expandtab
set fencs=ucs-bom,utf-8,euc-kr.latin1 " 한글 파일은 euc-kr로, 유니코드는 유니코드로
set fileencoding=utf-8 " 파일저장인코딩
set tenc=utf-8
set incsearch        " 키워드 입력시 점진적 검색
set history=1000
set t_Co=256
set notermguicolors
set clipboard=unnamed " use OS clipboard
" set undofile
" lazy drawing
set nolazyredraw
set ttyfast
set nocursorline
" set paste
set nosmartindent

autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
autocmd FileType yml setlocal ts=2 sts=2 sw=2 expandtab
autocmd FileType toml setlocal ts=2 sts=2 sw=2 expandtab
autocmd FileType hcl setlocal ts=2 sts=2 sw=2 expandtab
autocmd FileType go setlocal ts=4 sts=4 sw=4 expandtab
autocmd FileType go set list lcs=tab:\┊\ "(last character is a space...)
autocmd FileType go hi SpecialKey ctermfg=gray
autocmd FileType python let b:coc_root_patterns = ['.git', '.env']

au BufNewFile,BufRead Jenkinsfile setf groovy " Jenkinsfile syntax on

" For Neovim 0.1.3 and 0.1.4 - https://github.com/neovim/neovim/pull/2198
if (has('nvim'))
  let $NVIM_TUI_ENABLE_TRUE_COLOR = 1
endif

syntax on
set background=dark
colorscheme material

" General key mapping
nmap <Leader>a ^
nmap <Leader>s $
vmap <Leader>a ^
vmap <Leader>s $

noremap <C-S> :update<CR>
vnoremap <C-S> <C-C>:update<CR>
inoremap <C-S> <Esc>:update<CR>

nmap <leader>w :bp <BAR> bd #<CR>
nmap <Leader><Tab> :bn<CR>
nmap <Leader><Leader><Tab> :bp<CR>

noremap <S-Up> 5k
noremap <S-Down> 5j
noremap <S-Left> 20h
noremap <S-Right> 20l
" map <S-k> <S-Up>
" map <S-j> <S-Down>
" map <S-h> <S-Left>
" map <S-l> <S-Right>
noremap <S-K> 5k
noremap <S-J> 5j
noremap <S-H> 20h
noremap <S-L> 20l

map <Leader>z <C-W><Left>
map <Leader>x <C-w>w

noremap <C-q> :q!<CR>

" undo
map <C-z> :undo<CR>
" redo
map <S-z> :redo<CR>

" reload vim configuration
map <Leader><C-r> :so %<CR>

" search highlight disable
map q :nohl<CR>

" Copy current directory name to clipboard
nmap cap :let @*=expand("%:p:h")<CR>
nmap cp :let @+=expand("%")<cr>

:vnoremap < <gv
:vnoremap > >gv

" vim-airline
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#buffer_nr_show = 1
let g:airline_powerline_fonts = 1
let g:airline_theme = 'bubblegum'

" nerdtree ( https://github.com/preservim/nerdtree )
let g:NERDTreeWinSize=25
" let g:nerdtree_tabs_open_on_console_startup = 1
let NERDTreeShowHidden=1
nmap <Leader>q <plug>NERDTreeTabsToggle<CR>
nmap <Leader>r :NERDTreeFocus<cr>R<c-w><c-p>
nmap <C-j> :vertical resize+5<CR>
nmap <C-k> :vertical resize-5<CR>
nnoremap <leader>n :NERDTreeFind<CR>
let g:NERDTreeMouseMode = 3

" Start NERDTree and put the cursor back in the other window.
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

" Exit Vim if NERDTree is the only window remaining in the only tab.
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" auto refresh
autocmd BufWritePost * NERDTreeFocus | execute 'normal R' | wincmd p

let g:NERDTreeHighlightFolders = 1 " enables folder icon highlighting using exact match
let g:NERDTreeHighlightFoldersFullName = 1 " highlights the folder name

let g:NERDTreeAutoCenter=1


" indentLine
let g:indentLine_color_term = 239
let g:indentLine_setColors = 0
let g:indentLine_char = 'c'
let g:indentLine_char_list = ['|', '¦', '┆', '┊']

" nerdcommenter
" Add spaces after comment delimiters by default
let g:NERDSpaceDelims = 1
" Use compact syntax for prettified multi-line comments
let g:NERDCompactSexyComs = 1
" Align line-wise comment delimiters flush left instead of following code indentation
let g:NERDDefaultAlign = 'left'
" Set a language to use its alternate delimiters by default
let g:NERDAltDelims_java = 1
" Add your own custom formats or override the defaults
let g:NERDCustomDelimiters = { 'c': { 'left': '/**','right': '*/' } }
" Allow commenting and inverting empty lines (useful when commenting a region)
let g:NERDCommentEmptyLines = 1
" Enable trimming of trailing whitespace when uncommenting
let g:NERDTrimTrailingWhitespace = 1

" Always show the signcolumn, otherwise it would shift the text each time
" diagnostics appear/become resolved.
set signcolumn=yes

" Use tab for trigger completion with characters ahead and navigate.
" NOTE: There's always complete item selected by default, you may want to enable
" no select by `"suggest.noselect": true` in your configuration file.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
inoremap <silent><expr> <TAB>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

" Make <CR> to accept selected completion item or notify coc.nvim to format
" <C-g>u breaks current undo, please make your own choice.
inoremap <silent><expr> <TAB> coc#pum#visible() ? coc#pum#confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
inoremap <silent><expr> <c-space> coc#refresh()

function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <c-space> to trigger completion.
if has('nvim')
  inoremap <silent><expr> <c-space> coc#refresh()
else
  inoremap <silent><expr> <c-@> coc#refresh()
endif

" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" GoTo code navigation.
nmap <silent> gt :call CocAction('jumpDefinition', 'vsplit')<CR>
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window.
nnoremap <silent> K :call ShowDocumentation()<CR>

function! ShowDocumentation()
  if CocAction('hasProvider', 'hover')
    call CocActionAsync('doHover')
  else
    call feedkeys('K', 'in')
  endif
endfunction

" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)

" Formatting selected code.
xmap <leader>f  <Plug>(coc-format-selected)
nmap <leader>f  <Plug>(coc-format-selected)

augroup mygroup
  autocmd!
  " Setup formatexpr specified filetype(s).
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  " Update signature help on jump placeholder.
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end

" Applying codeAction to the selected region.
" Example: `<leader>aap` for current paragraph
xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)

" Remap keys for applying codeAction to the current buffer.
nmap <leader>ac  <Plug>(coc-codeaction)
" Apply AutoFix to problem on the current line.
nmap <leader>qf  <Plug>(coc-fix-current)

" Run the Code Lens action on the current line.
nmap <leader>cl  <Plug>(coc-codelens-action)

" Map function and class text objects
" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
omap ic <Plug>(coc-classobj-i)
xmap ac <Plug>(coc-classobj-a)
omap ac <Plug>(coc-classobj-a)

" Remap <C-f> and <C-b> for scroll float windows/popups.
if has('nvim-0.4.0') || has('patch-8.2.0750')
  nnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
  nnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
  inoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"
  inoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"
  vnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
  vnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
endif

" Add `:Format` command to format current buffer.
command! -nargs=0 Format :call CocActionAsync('format')

" Add `:Fold` command to fold current buffer.
command! -nargs=? Fold :call     CocAction('fold', <f-args>)

" Add `:OR` command for organize imports of the current buffer.
command! -nargs=0 OR   :call     CocActionAsync('runCommand', 'editor.action.organizeImport')

" Add (Neo)Vim's native statusline support.
" NOTE: Please see `:h coc-status` for integrations with external plugins that
" provide custom statusline: lightline.vim, vim-airline.
set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}

" Mappings for CoCList
" Show all diagnostics.
nnoremap <silent><nowait> <space>a  :<C-u>CocList diagnostics<cr>
" Manage extensions.
nnoremap <silent><nowait> <space>e  :<C-u>CocList extensions<cr>
" Show commands.
nnoremap <silent><nowait> <space>c  :<C-u>CocList commands<cr>
" Find symbol of current document.
nnoremap <silent><nowait> <space>o  :<C-u>CocList outline<cr>
" Search workspace symbols.
nnoremap <silent><nowait> <space>s  :<C-u>CocList -I symbols<cr>
" Do default action for next item.
nnoremap <silent><nowait> <space>j  :<C-u>CocNext<CR>
" Do default action for previous item.
nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
" Resume latest coc list.
nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>

let g:coc_global_extensions = [
    \'coc-markdownlint',
    \'coc-highlight',
    \'coc-go',
    \'coc-pyright',
    \'coc-json', 
    \'coc-git',
    \'coc-yaml',
    \'coc-tsserver',
    \'coc-marketplace'
\]

" vim-terraform setting
let g:terraform_align=1
let g:terraform_fold_sections=0
let g:terraform_fmt_on_save=1

" vim-easymotion setting
map  f <Plug>(easymotion-bd-f)
nmap f <Plug>(easymotion-overwin-f)
" s{char}{char} to move to {char}{char}
nmap s <Plug>(easymotion-overwin-f2)

" vim-ansible set up                               
let g:ansible_unindent_after_newline = 1           
let g:ansible_attribute_highlight = "ob"           
let g:ansible_name_highlight = 'd'                 
let g:ansible_extra_keywords_highlight = 1         
let g:ansible_normal_keywords_highlight = 'Constant'
let g:ansible_with_keywords_highlight = 'Constant'
let g:ansible_template_syntaxes = { '*.rb.j2': 'ruby' }

" fzf
set rtp+="$(which fzf)"
let g:fzf_preview_window = ['right:50%', 'ctrl-/']
map <C-t> :Files<cr>
map <C-f> :BLines<cr>
map <S-f> :Rg<cr>
map <C-x> :Buffers<cr>

" blamer (https://github.com/APZelos/blamer.nvim)
let g:blamer_enabled = 1
let g:blamer_delay = 500

" diffview ( https://github.com/sindrets/diffview.nvim )
nmap vd :DiffviewOpen<cr>
nmap cd :DiffviewClose<cr>

" vim-choosewin ( https://github.com/t9md/vim-choosewin )
nmap - <Plug>(choosewin)
let g:choosewin_overlay_enable = 1

" vim-go
let g:go_def_mode='gopls'
let g:go_info_mode='gopls'

let g:go_fmt_command = "goimports"
let g:go_autodetect_gopath = 1
let g:go_list_type = "quickfix"
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1
let g:go_highlight_function_calls = 1
let g:go_highlight_extra_types = 1
let g:go_highlight_generate_tags = 1

" Common Go commands
au FileType go nmap <leader>r <Plug>(go-run)
au FileType go nmap <leader>b <Plug>(go-build)
au FileType go nmap <leader>t <Plug>(go-test)
au FileType go nmap <leader>c <Plug>(go-coverage-toggle)
au FileType go nmap <Leader>e <Plug>(go-rename)
au FileType go nmap <Leader>s <Plug>(go-implements)
au FileType go nmap <Leader>i <Plug>(go-info)

" Far.vim
let g:far#enable_undo=1
au FileType far_vim map <buffer><silent>q :bw<cr>

" normal mode에서 G를 눌렀을 때 커서를 텍스트 끝으로 이동하는 vimrc 설정 추가
nnoremap T $

" copilot
imap <silent> <C-u> <Plug>(copilot-next)
imap <silent> <C-i> <Plug>(copilot-previous)
imap <silent> <C-o> <Plug>(copilot-dismiss)
