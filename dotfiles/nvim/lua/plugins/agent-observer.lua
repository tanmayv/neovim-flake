return {
  "local/agent-observer",
  dir = vim.fn.stdpath("config") .. "/lua/agent-observer",
  config = function()
    require("agent-observer").setup()
  end,
  keys = {
    { "<leader>ao", "<cmd>AgentObserverToggle<cr>", desc = "Toggle Agent Observer" },
  },
}
