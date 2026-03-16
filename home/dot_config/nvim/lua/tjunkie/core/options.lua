local opt = vim.opt
local cmd = vim.cmd

cmd("let g:netrw_liststyle = 3")

opt.relativenumber = true
opt.number = true

-- tabs & indentation
opt.tabstop = 2       -- 2 spaces for tabs (prettier default)
opt.softtabstop = 2   -- see multiple spaces as tabstops so <BS> does the right thing
opt.shiftwidth = 2    -- 2 spaces for indent width
opt.expandtab = true  -- expand tab to spaces
opt.autoindent = true -- copy indent from current line when starting new one
opt.showmatch = true  -- show matching brackets

opt.wrap = false

-- search settings
opt.hlsearch = true   -- highlight search results
opt.ignorecase = true -- ignore case when searching
opt.smartcase = true  -- if you include mixed case in your search, assumes you want case-sensitive

opt.cursorline = true -- enable line of current position

-- turn on termguicolors for tokyonight colorscheme to work
-- (have to use iterm2 or any other true color terminal)
opt.termguicolors = true
opt.background = "dark" -- colorschemes that can be light or dark will be made dark
opt.signcolumn = "yes"  -- show sign column so that text doesn't shift

-- backspace
opt.backspace = "indent,eol,start" -- allow backspace on indent, end of line or insert mode start position

--This part is to fix insert mode cursor missing
opt.guicursor = "a:block"
opt.guicursor = "n-v-c:blinkon0"
opt.guicursor = "i:blinkon1"

-- clipboard
opt.clipboard:append("unnamedplus") -- use system clipboard as default register

-- split windows
opt.splitright = true -- split vertical window to the right
opt.splitbelow = true -- split horizontal window to the bottom

-- turn off swapfile
opt.swapfile = false

-- auto-reload files changed externally (e.g. by Claude Code)
opt.autoread = true
opt.updatetime = 1000 -- check for external changes every 1s when idle (default: 4000ms)
