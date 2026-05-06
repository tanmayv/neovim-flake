return {
  "local/agent-observer",
  dir = vim.fn.stdpath("config") .. "/lua/agent-observer",
  lazy = false, -- Load early to start watching
  config = function()
    require("agent-observer").setup()
  end,
  keys = {
    { "<leader>ao", "<cmd>AgentObserverToggle<cr>", desc = "Toggle Agent Observer" },
  },
}
