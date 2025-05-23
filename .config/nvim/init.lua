-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

vim.cmd("filetype indent off")
vim.cmd("filetype plugin indent off")
vim.opt.autoindent = false

vim.api.nvim_del_keymap("n", "Y")
vim.opt.mouse = ""
vim.opt.modeline = true

--vim.opt.diffopt = "internal,filler,closeoff,linematch:60"
--vim.opt.diffopt = "filler,internal,closeoff,algorithm:histogram,context:5,linematch:60"
vim.opt.diffopt = "internal,filler,closeoff,indent-heuristic,linematch:60,algorithm:histogram"

vim.opt.list = true
vim.opt.listchars:append {
  tab = "▸.",
  trail = "·",
}

-- search settings
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local plugins = {
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  {
    "nvim-telescope/telescope.nvim", branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" }
  },
--  {
--    "nvim-treesitter/nvim-treesitter", build = ":TSUpdate",
--    config = function()
--      local configs = require("nvim-treesitter.configs")
--      configs.setup({
--        ensure_installed = { "bash", "c", "go", "javascript", "lua", "python", "ruby", "vim", "yaml" },
--        sync_install = false,
--        highlight = { enable = true },
--        indent = { enable = false },
--      })
--    end
--  },
}
require("lazy").setup(plugins, {})

require("catppuccin").setup()
vim.cmd.colorscheme "catppuccin"

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Telescope live grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })
