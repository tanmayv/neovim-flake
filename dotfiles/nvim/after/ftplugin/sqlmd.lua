-- 1. Verify Otter is available
local status_ok, otter = pcall(require, "otter")
if not status_ok then return end

vim.schedule(function()
  -- OPTIONAL: Force a synchronous parse just to be absolutely sure
  -- usually not needed with vim.schedule, but good for safety
  if vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] then vim.treesitter.get_parser():parse() end

  -- Activate Otter
  otter.activate({ "sql" }, true, true, nil)

  -- Notify (moved inside schedule to confirm timing)
  vim.notify("🦦 Otter SQL Activated (Deferred)", vim.log.levels.INFO)
end)
