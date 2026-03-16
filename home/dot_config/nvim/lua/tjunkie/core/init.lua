require("tjunkie.core.options")
require("tjunkie.core.keymaps")
require("tjunkie.core.which-key-settings")

-- Auto-reload files changed by external tools (e.g. Claude Code)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  command = "checktime",
})
