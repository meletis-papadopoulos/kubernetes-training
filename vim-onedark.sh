#!/usr/bin/env bash
# =============================================================================
# vim-onedark.sh - configure Vim defaults and install a dark theme.
#
# Usage:
#   ./vim-onedark.sh
#   ./vim-onedark.sh --restore
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
VIMRC="/etc/vim/vimrc"
VIMRC_LOCAL="/etc/vim/vimrc.local"
VIMRC_BACKUP="/etc/vim/vimrc.before-onedark"
COLOR_DIR="/usr/share/vim/vimfiles/colors"
COLOR_FILE="${COLOR_DIR}/onedark-custom.vim"

MANAGED_START='" === MANAGED VIM SETTINGS ==='
MANAGED_END='" === END MANAGED VIM SETTINGS ==='

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $0            Apply Vim configuration
  $0 --restore  Remove managed Vim configuration
EOF
}

require_root() {
  if [[ "${UID}" -ne 0 ]]; then
    echo "Run as root"
    exit 1
  fi
}

remove_managed_block() {
  touch "${VIMRC_LOCAL}"
  sed -i "/${MANAGED_START}/,/${MANAGED_END}/d" "${VIMRC_LOCAL}"
}

remove_legacy_direct_config() {
  if [[ -f "${VIMRC}" ]] && grep -q '^"Custom Vim settings$' "${VIMRC}"; then
    [[ -f "${VIMRC_BACKUP}" ]] || cp -p "${VIMRC}" "${VIMRC_BACKUP}"
    sed -i '/^"Custom Vim settings$/,$d' "${VIMRC}"
  fi
}

restore_vimrc() {
  remove_managed_block
  rm -f "${COLOR_FILE}"

  if [[ -f "${VIMRC_BACKUP}" ]]; then
    cp -p "${VIMRC_BACKUP}" "${VIMRC}"
    echo "Restored ${VIMRC} from ${VIMRC_BACKUP}"
  else
    echo "Removed managed Vim configuration"
  fi
}

# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------
require_root

case "${1:-}" in
  "")
    ;;
  --restore)
    restore_vimrc
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
remove_managed_block
remove_legacy_direct_config

mkdir -p "${COLOR_DIR}"

# ---------------------------------------------------------------------------
# Colorscheme
# ---------------------------------------------------------------------------
cat > "${COLOR_FILE}" <<'EOF'
" onedark-custom.vim
" Atom One Dark / VS Code One Dark-like Vim theme

set background=dark
highlight clear

if exists("syntax_on")
  syntax reset
endif

let g:colors_name = "onedark-custom"

" UI
hi Normal       guifg=#ABB2BF guibg=#282C34 gui=NONE ctermfg=145 ctermbg=236 cterm=NONE
hi LineNr       guifg=#495162 guibg=#282C34 gui=NONE ctermfg=59  ctermbg=236 cterm=NONE
hi CursorLine   guifg=NONE    guibg=#383E4A gui=NONE ctermfg=NONE ctermbg=238 cterm=NONE
hi CursorLineNr guifg=#D7DAE0 guibg=#383E4A gui=bold ctermfg=188 ctermbg=238 cterm=bold
hi SignColumn   guifg=#495162 guibg=#282C34 gui=NONE ctermfg=59  ctermbg=236 cterm=NONE
hi Visual       guifg=NONE    guibg=#3E4451 gui=NONE ctermfg=NONE ctermbg=238 cterm=NONE
hi Search       guifg=#282C34 guibg=#E5C07B gui=NONE ctermfg=236 ctermbg=180 cterm=NONE
hi IncSearch    guifg=#282C34 guibg=#D19A66 gui=NONE ctermfg=236 ctermbg=173 cterm=NONE
hi MatchParen   guifg=#E5C07B guibg=#3E4451 gui=bold ctermfg=180 ctermbg=238 cterm=bold
hi NonText      guifg=#3E4452 guibg=#282C34 gui=NONE ctermfg=238 ctermbg=236 cterm=NONE
hi EndOfBuffer  guifg=#282C34 guibg=#282C34 gui=NONE ctermfg=236 ctermbg=236 cterm=NONE
hi StatusLine   guifg=#D7DAE0 guibg=#21252B gui=NONE ctermfg=188 ctermbg=235 cterm=NONE
hi StatusLineNC guifg=#9DA5B4 guibg=#21252B gui=NONE ctermfg=145 ctermbg=235 cterm=NONE

" Generic syntax
hi Comment      guifg=#676F7D guibg=#282C34 gui=NONE ctermfg=60  ctermbg=236 cterm=NONE
hi String       guifg=#E5C07B guibg=#282C34 gui=NONE ctermfg=180 ctermbg=236 cterm=NONE
hi Character    guifg=#E5C07B guibg=#282C34 gui=NONE ctermfg=180 ctermbg=236 cterm=NONE
hi Number       guifg=#C678DD guibg=#282C34 gui=NONE ctermfg=176 ctermbg=236 cterm=NONE
hi Boolean      guifg=#C678DD guibg=#282C34 gui=NONE ctermfg=176 ctermbg=236 cterm=NONE
hi Constant     guifg=#56B6C2 guibg=#282C34 gui=NONE ctermfg=73  ctermbg=236 cterm=NONE
hi Identifier   guifg=#ABB2BF guibg=#282C34 gui=NONE ctermfg=145 ctermbg=236 cterm=NONE
hi Function     guifg=#98C379 guibg=#282C34 gui=NONE ctermfg=114 ctermbg=236 cterm=NONE
hi Statement    guifg=#98C379 guibg=#282C34 gui=NONE ctermfg=114 ctermbg=236 cterm=NONE
hi Conditional  guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi Repeat       guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi Keyword      guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi Operator     guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi PreProc      guifg=#61AFEF guibg=#282C34 gui=NONE ctermfg=75  ctermbg=236 cterm=NONE
hi Type         guifg=#56B6C2 guibg=#282C34 gui=NONE ctermfg=73  ctermbg=236 cterm=NONE
hi Special      guifg=#56B6C2 guibg=#282C34 gui=NONE ctermfg=73  ctermbg=236 cterm=NONE
hi Error        guifg=#F44747 guibg=#282C34 gui=NONE ctermfg=203 ctermbg=236 cterm=NONE
hi Todo         guifg=#282C34 guibg=#E5C07B gui=bold ctermfg=236 ctermbg=180 cterm=bold

" Shell syntax
hi shComment       guifg=#676F7D guibg=#282C34 gui=NONE ctermfg=60  ctermbg=236 cterm=NONE
hi shShebang       guifg=#676F7D guibg=#282C34 gui=NONE ctermfg=60  ctermbg=236 cterm=NONE
hi shStatement     guifg=#98C379 guibg=#282C34 gui=NONE ctermfg=114 ctermbg=236 cterm=NONE
hi shSet           guifg=#98C379 guibg=#282C34 gui=NONE ctermfg=114 ctermbg=236 cterm=NONE
hi shAlias         guifg=#98C379 guibg=#282C34 gui=NONE ctermfg=114 ctermbg=236 cterm=NONE
hi shFunction      guifg=#98C379 guibg=#282C34 gui=NONE ctermfg=114 ctermbg=236 cterm=NONE
hi shConditional   guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi shLoop          guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi shFor           guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi shCase          guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi shVariable      guifg=#ABB2BF guibg=#282C34 gui=NONE ctermfg=145 ctermbg=236 cterm=NONE
hi shVariableDef   guifg=#ABB2BF guibg=#282C34 gui=NONE ctermfg=145 ctermbg=236 cterm=NONE
hi shDeref         guifg=#61AFEF guibg=#282C34 gui=NONE ctermfg=75  ctermbg=236 cterm=NONE
hi shDerefVar      guifg=#61AFEF guibg=#282C34 gui=NONE ctermfg=75  ctermbg=236 cterm=NONE
hi shDerefSimple   guifg=#61AFEF guibg=#282C34 gui=NONE ctermfg=75  ctermbg=236 cterm=NONE
hi shDerefPattern  guifg=#61AFEF guibg=#282C34 gui=NONE ctermfg=75  ctermbg=236 cterm=NONE
hi shString        guifg=#E5C07B guibg=#282C34 gui=NONE ctermfg=180 ctermbg=236 cterm=NONE
hi shQuote         guifg=#E5C07B guibg=#282C34 gui=NONE ctermfg=180 ctermbg=236 cterm=NONE
hi shDoubleQuote   guifg=#E5C07B guibg=#282C34 gui=NONE ctermfg=180 ctermbg=236 cterm=NONE
hi shSingleQuote   guifg=#E5C07B guibg=#282C34 gui=NONE ctermfg=180 ctermbg=236 cterm=NONE
hi shNumber        guifg=#C678DD guibg=#282C34 gui=NONE ctermfg=176 ctermbg=236 cterm=NONE
hi shOption        guifg=#61AFEF guibg=#282C34 gui=NONE ctermfg=75  ctermbg=236 cterm=NONE
hi shTestOpr       guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi shOperator      guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi shCmdSubRegion  guifg=#ABB2BF guibg=#282C34 gui=NONE ctermfg=145 ctermbg=236 cterm=NONE
hi shCommandSub    guifg=#ABB2BF guibg=#282C34 gui=NONE ctermfg=145 ctermbg=236 cterm=NONE

" YAML syntax
hi yamlBlockMappingKey   guifg=#E06C75 guibg=#282C34 gui=NONE ctermfg=168 ctermbg=236 cterm=NONE
hi yamlKeyValueDelimiter guifg=#56B6C2 guibg=#282C34 gui=NONE ctermfg=73  ctermbg=236 cterm=NONE
hi yamlPlainScalar       guifg=#ABB2BF guibg=#282C34 gui=NONE ctermfg=145 ctermbg=236 cterm=NONE
hi yamlString            guifg=#E5C07B guibg=#282C34 gui=NONE ctermfg=180 ctermbg=236 cterm=NONE
hi yamlInteger           guifg=#C678DD guibg=#282C34 gui=NONE ctermfg=176 ctermbg=236 cterm=NONE
hi yamlBoolean           guifg=#C678DD guibg=#282C34 gui=NONE ctermfg=176 ctermbg=236 cterm=NONE
EOF

# ---------------------------------------------------------------------------
# Vim settings
# ---------------------------------------------------------------------------
cat >> "${VIMRC_LOCAL}" <<'EOF'

" === MANAGED VIM SETTINGS ===
set number
set cursorline
set autoindent
set expandtab
set tabstop=2
set shiftwidth=2
set softtabstop=2
set ignorecase
set smartcase
set incsearch
set visualbell

if exists('+termguicolors')
  set termguicolors
endif

syntax enable
filetype plugin indent on
colorscheme onedark-custom

autocmd BufNewFile,BufRead *.sh setlocal filetype=sh tabstop=2 shiftwidth=2 softtabstop=2 expandtab
autocmd BufNewFile,BufRead *.yml,*.yaml setlocal filetype=yaml tabstop=2 shiftwidth=2 softtabstop=2 expandtab
autocmd BufNewFile,BufRead * setlocal formatoptions-=cro
" === END MANAGED VIM SETTINGS ===
EOF

echo "Applied Vim settings."
