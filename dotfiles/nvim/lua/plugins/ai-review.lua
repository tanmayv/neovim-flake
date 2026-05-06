return {
  {
    "tanmayv/ai-review.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = "VeryLazy",
    cmd = { "MeowReview" },
    config = function()
      vim.g.meow_review = {
        store_path = ".cache/meow-review/annotations.json",
      }

      require("meow.review").setup({})
    end,
    keys = {
      { "<leader>ra", "<Plug>(MeowReviewAdd)", mode = { "n", "v" }, desc = "Add Review Comment" },
      { "<leader>rd", "<Plug>(MeowReviewDelete)", mode = { "n", "v" }, desc = "Delete Review Comment" },
      { "<leader>re", "<Plug>(MeowReviewEdit)", desc = "Edit Review Comment" },
      { "<leader>rv", "<Plug>(MeowReviewView)", desc = "View Review Comment" },
      { "<leader>rE", "<Plug>(MeowReviewExport)", desc = "Export Review" },
      { "<leader>rX", "<Plug>(MeowReviewExportAndClear)", desc = "Export and Clear" },
      { "<leader>rf", "<cmd>MeowReview export file<cr>", desc = "Export to File" },
      { "<leader>rc", "<Plug>(MeowReviewClear)", desc = "Clear All Comments" },
      { "<leader>rg", "<Plug>(MeowReviewGoto)", desc = "Go to Review Comment" },
      { "<leader>rG", "<Plug>(MeowReviewGotoFile)", desc = "Go to Comment in File" },
      { "<leader>rt", "<Plug>(MeowReviewGotoType)", desc = "Go to Comment by Type" },
      { "<leader>rR", "<Plug>(MeowReviewResolve)", desc = "Resolve Comment" },
      { "<leader>rA", "<Plug>(MeowReviewResolveAll)", desc = "Resolve All Comments" },
      { "<leader>rr", "<Plug>(MeowReviewGoto)", desc = "Go to Review Comments" },
      { "]r", "<Plug>(MeowReviewNext)", desc = "Next Review Comment" },
      { "[r", "<Plug>(MeowReviewPrev)", desc = "Previous Review Comment" },
    },
  },
}
