-- This file simply bootstraps the installation of Lazy.nvim and then calls other files for execution
-- This file doesn't necessarily need to be touched, BE CAUTIOUS editing this file and proceed at your own risk.
local google_vim_config = "/usr/share/vim/google/glug/bootstrap.vim"

if vim.fn.filereadable(google_vim_config) == 1 then
  -- Source Google's default Vim configuration
  -- This will also handle 'filetype plugin indent on'

  vim.cmd("source " .. google_vim_config)

  -- Load Google plugins using Glug
  -- Add your desired Glug commands here
  vim.cmd [[Glug relatedfiles]]
  vim.cmd [[Glug codefmt]]
  -- Example with options:
  -- vim.cmd [[Glug relatedfiles plugin[mappings]]]

  print "Google Vim settings and Glug plugins loaded."
else
  print("Google Vim config not found at " .. google_vim_config .. ", skipping.")
end

local lazypath = vim.env.LAZY or vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not (vim.env.LAZY or (vim.uv or vim.loop).fs_stat(lazypath)) then
  -- stylua: ignore
  local result = vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath })
  if vim.v.shell_error ~= 0 then
    -- stylua: ignore
    vim.api.nvim_echo(
    { { ("Error cloning lazy.nvim:\n%s\n"):format(result), "ErrorMsg" }, { "Press any key to exit...", "MoreMsg" } },
      true, {})
    vim.fn.getchar()
    vim.cmd.quit()
  end
end

vim.opt.rtp:prepend(lazypath)

-- validate that lazy is available
if not pcall(require, "lazy") then
  -- stylua: ignore
  vim.api.nvim_echo(
  { { ("Unable to load lazy from: %s\n"):format(lazypath), "ErrorMsg" }, { "Press any key to exit...", "MoreMsg" } },
    true, {})
  vim.fn.getchar()
  vim.cmd.quit()
end

require "lazy_setup"
require "polish"

-- Only yank to system clipboard
-- vim.keymap.set({ "n", "v" }, "y", [["+y]])
-- vim.keymap.set("n", "Y", [["+Y]])
--
-- vim.keymap.set("n", "<leader>pa", [[:let @+ = expand('%:p')<CR>]], { desc = "Copy absolute path" })
-- -- Copy relative path
-- vim.keymap.set("n", "<leader>pr", [[:let @+ = expand('%')<CR>]], { desc = "Copy relative path" })

-- Auto read file when its changed by ai agent
vim.o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  command = "if mode() != 'c' | checktime | endif",
  pattern = "*",
})
vim.opt.swapfile = false

-- Conditionally load cloudtop configuration
pcall(require, "cloudtop_init")
pcall(require, "sqlite_path")
