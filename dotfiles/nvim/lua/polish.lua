-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here

local function set_transparency(transparent)
  if transparent then
    local groups = {
      "Normal",
      "NormalNC",
      "NormalSB",
      "SignColumn",
      "FoldColumn",
      "EndOfBuffer",
      "NeoTreeNormal",
      "NeoTreeNormalNC",
      "NeoTreeEndOfBuffer",
    }
    for _, group in ipairs(groups) do
      vim.api.nvim_set_hl(0, group, { bg = "NONE" })
    end
    vim.g.transparent_enabled = true
  else
    if vim.g.colors_name then vim.cmd("colorscheme " .. vim.g.colors_name) end
    vim.g.transparent_enabled = false
  end
end

vim.api.nvim_create_user_command("Focus", function()
  set_transparency(not vim.g.transparent_enabled)
  local notify = require("astrocore").notify
  notify(string.format("Transparency %s", vim.g.transparent_enabled and "Enabled" or "Disabled"))
end, {})

-- Binding to toggle transparency
-- Using <Leader>tf (Toggle Focus) since <Leader>focus is too long for a direct chord
vim.keymap.set("n", "<Leader>tf", ":Focus<CR>", { desc = "Toggle Transparency (Focus)" })

-- Enable transparency on startup
set_transparency(true)

-- 3. Prevent "Replace after Paste" from overwriting your register
-- so your clipboard remains unchanged after you paste over something.
vim.keymap.set("v", "p", '"_dP', { desc = "Paste without overwriting clipboard" })

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    -- x = visual mode
    -- ic = selection target
    -- <buffer> = true ensures it only lives in the markdown file
    vim.keymap.set("x", "ic", " <Esc>:<C-u>silent! ?^```<CR>jV/^```<CR>k", {
      buffer = true,
      desc = "Select inside code block",
    })

    -- Optional: 'ac' for around code block (includes the backticks)
    vim.keymap.set("x", "ac", " <Esc>:<C-u>silent! ?^```<CR>V/^```<CR>", {
      buffer = true,
      desc = "Select around code block",
    })
  end,
})
