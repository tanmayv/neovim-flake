return {
  {
    "DAmesberger/sc-im.nvim",
    config = function()
      require("sc-im").setup {
        ft = "scim",
        include_sc_file = true,
        update_sc_from_md = true,
        link_fmt = 1,
        split = "floating",
        float_config = {
          height = 0.9,
          width = 0.9,
          style = "minimal",
          border = "single",
          hl = "Normal",
          blend = 0,
        },
      }
    end,
    keys = {
      { "<leader>s", group = "sc-im" },
      { "<leader>sc", "<cmd>lua require('sc-im').open_in_scim()<cr>", desc = "Open table in sc-im" },
      { "<leader>sl", "<cmd>lua require('sc-im').open_in_scim(true)<cr>", desc = "Open table in sc-im" },
      { "<leader>sp", "<cmd>lua require('sc-im').open_in_scim(false)<cr>", desc = "Open plain table in sc-im" },
      { "<leader>st", "<cmd>lua require('sc-im').toggle(true)<cr>", desc = "Toggle sc-im link format" },
      { "<leader>sr", "<cmd>lua require('sc-im').rename()<cr>", desc = "Rename linked sc-im file" },
      { "<leader>su", "<cmd>lua require('sc-im').update()<cr>", desc = "Recalculate Markdown table" },
      { "<leader>sU", "<cmd>lua require('sc-im').update(true)<cr>", desc = "Update sc file and Markdown table" },
    },
  },
  {
    "OXY2DEV/markview.nvim",
    ft = "markdown",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons"
    },
    config = function()
      require("markview").setup()
      
      -- Enable wrap for markdown files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function()
          vim.opt_local.wrap = true
        end,
      })
    end,
  },
  {
    "tanmayv/tasks.nvim",
    dependencies = {
      "kkharji/sqlite.lua", -- Required for database operations
    },
    keys = {
      { "<leader>tt", function() require("task_manager.telescope").tasks() end, desc = "View [T]asks" },
      {
        "<leader>tA",
        function()
          require("task_manager.telescope").tasks {
            status = { "todo", "in_progress", "done", "cancelled" },
          }
        end,
        desc = "View [T]asks [A]ll",
      },
      {
        "<leader>tw",
        function()
          local workspace = nil
          if vim.env.TMUX then
            workspace = vim.fn.system("tmux display-message -p '#S'"):gsub("\n", "")
          end
          if workspace and workspace ~= "" then
            require("task_manager.telescope").tasks { project = workspace }
          else
            require("task_manager.telescope").tasks()
          end
        end,
        desc = "View [T]asks from @[w]ork",
      },
      {
        "<leader>ta",
        function()
          local workspace = nil
          if vim.env.TMUX then
            workspace = vim.fn.system("tmux display-message -p '#S'"):gsub("\n", "")
          end
          if workspace and workspace ~= "" then
            vim.cmd(string.format("TaskAdd %s", workspace))
          else
            vim.cmd "TaskAdd"
          end
        end,
        desc = "Task [A]dd",
      },
      { "<leader>tu", function() require("task_manager.telescope").tasks { tags = "urgent" } end, desc = "View [T]asks #urgent" },
      {
        "<leader>td",
        function() require("task_manager.telescope").tasks { tags = { "daily", "now" }, match_any_tag = true } end,
        desc = "View Daily Tasks",
      },
      { "<leader>tx", "<cmd>TaskToggle<CR>", desc = "Toggle task done" },
    },
    config = function()
      require("task_manager").setup {
        -- The directories where you keep your task markdown files
        directories = { vim.fn.expand "~/pkm" },

        -- Where the SQLite database will be stored (defaults to ~/.local/share/nvim/task_manager.db)
        db_path = vim.fn.stdpath "data" .. "/task_manager.db",
        inbox_file = vim.fn.expand "~/pkm/tasks.md",
        auto_tags = {
          ["/daily/"] = { "daily" },
        },
      }
      require("task_manager").setup_lsp()
    end,
  },
}
