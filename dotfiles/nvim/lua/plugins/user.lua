---@type LazySpec
return {

  -- == Examples of Adding Plugins ==
  -- Add this to your user config
  {
    "AstroNvim/astrocore",
    ---@type AstroCoreOpts
    opts = {
      filetypes = {
        extension = {
          sqlmd = "sqlmd.markdown",
          pi = "python",
        },
        filename = {
          ["pb.txt"] = "pbtxt",
        },
        pattern = {
          [".*%.pb%.txt"] = "pbtxt",
        },
      },
      autocmds = {
        pbtxt_treesitter = {
          {
            event = "FileType",
            pattern = "pbtxt",
            callback = function() vim.treesitter.language.register("textproto", "pbtxt") end,
          },
        },
        -- Force Treesitter to use the markdown parser for this new type
        sqlmd_treesitter = {
          {
            event = "FileType",
            pattern = "sqlmd.markdown",
            callback = function() vim.treesitter.language.register("markdown", "sqlmd.markdown") end,
          },
        },
      },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if opts.ensure_installed ~= "all" then
        opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "textproto" })
      end
    end,
  },
  "andweeb/presence.nvim",
  {
    "ray-x/lsp_signature.nvim",
    event = "BufRead",
    config = function() require("lsp_signature").setup() end,
  },

  -- == Examples of Overriding Plugins ==

  -- customize dashboard options
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = table.concat({
            "      ___           ___                         ___     ",
            "     /\\__\\         /\\  \\         _____         /\\__\\    ",
            "    /:/  /        /::\\  \\       /::\\  \\       /:/ _/_   ",
            "   /:/  /        /:/\\:\\  \\     /:/\\:\\  \\     /:/ /\\__\\  ",
            "  /:/  /  ___   /:/  \\:\\  \\   /:/  \\:\\__\\   /:/ /:/ _/_ ",
            " /:/__/  /\\__\\ /:/__/ \\:\\__\\ /:/__/ \\:|__| /:/_/:/ /\\__\\",
            " \\:\\  \\ /:/  / \\:\\  \\ /:/  / \\:\\  \\ /:/  / \\:\\/:/ /:/  /",
            "  \\:\\  /:/  /   \\:\\  /:/  /   \\:\\  /:/  /   \\::/_/:/  / ",
            "   \\:\\/:/  /     \\:\\/:/  /     \\:\\/:/  /     \\:\\/:/  /  ",
            "    \\::/  /       \\::/  /       \\::/  /       \\::/  /   ",
            " \\/__/         \\/__/         \\/__/         \\/__/",
          }, "\n"),
        },
      },
    },
  },

  -- You can disable default plugins as follows:
  { "max397574/better-escape.nvim", enabled = false },

  -- You can also easily customize additional setup of plugins that is outside of the plugin's setup call
  {
    "L3MON4D3/LuaSnip",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.luasnip"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom luasnip configuration such as filetype extend or custom snippets
      local luasnip = require "luasnip"
      luasnip.filetype_extend("javascript", { "javascriptreact" })
    end,
  },
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
    },
  },
  {
    "windwp/nvim-autopairs",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.nvim-autopairs"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom autopairs configuration such as custom rules
      local npairs = require "nvim-autopairs"
      local Rule = require "nvim-autopairs.rule"
      local cond = require "nvim-autopairs.conds"
      npairs.add_rules(
        {
          Rule("$", "$", { "tex", "latex" })
            -- don't add a pair if the next character is %
            :with_pair(cond.not_after_regex "%%")
            -- don't add a pair if  the previous character is xxx
            :with_pair(
              cond.not_before_regex("xxx", 3)
            )
            -- don't move right when repeat character
            :with_move(cond.none())
            -- don't delete if the next character is xx
            :with_del(cond.not_after_regex "xx")
            -- disable adding a newline when you press <cr>
            :with_cr(cond.none()),
        },
        -- disable for .vim files, but it work for another filetypes
        Rule("a", "a", "-vim")
      )
    end,
  },
  {
    "zk-org/zk-nvim",
    config = function()
      vim.env.ZK_NOTEBOOK_DIR = vim.fn.expand "~/pkm"
      require("zk").setup {
        picker_options = {
          telescope = require("telescope.themes").get_ivy(),
        },
      }

      _G.zk_wrapper = function()
        local Job = require "plenary.job"
        Job:new({
          command = "zsh",
          cwd = vim.fn.getcwd(),
          args = { "-c", "nn --print-path" },
          on_exit = function(j, _)
            local stdout = j:result()
            local last_out = stdout[#stdout]
            vim.schedule(function()
              if string.match(last_out, "%.md$") then
                vim.cmd.edit(last_out)
              else
                print(vim.inspect(stdout))
              end
            end)
          end,
        }):start() -- or start()
        print "Creating new note ..."
      end

      local opts = { noremap = true, silent = false }

      -- Create a new note after asking for its title.
      vim.api.nvim_set_keymap("n", "<leader>zn", ":lua zk_wrapper()<cr>", opts)

      -- Open notes.
      vim.api.nvim_set_keymap("n", "<leader>zo", "<Cmd>ZkNotes { sort = { 'modified' } }<CR>", opts)
      vim.api.nvim_set_keymap(
        "n",
        "<leader>zwo",
        "<Cmd>ZkNotes { sort = { 'modified' }, tags = { 'workspace' } }<CR>",
        opts
      )
      -- Open notes associated with the selected tags.
      vim.api.nvim_set_keymap("n", "<leader>zt", "<Cmd>ZkTags<CR>", opts)

      -- Search for the notes matching a given query.
      vim.api.nvim_set_keymap(
        "n",
        "<leader>zf",
        "<Cmd>ZkNotes { sort = { 'modified' }, match = { vim.fn.input('Search: ') } }<CR>",
        opts
      )
      vim.api.nvim_set_keymap("n", "gd", "<Cmd>lua vim.lsp.buf.definition()<CR>", opts)
      vim.api.nvim_set_keymap("n", "<leader>zb", "<Cmd>ZkBacklinks<CR>", opts)
      vim.api.nvim_set_keymap("n", "<leader>zl", "<Cmd>ZkLinks<CR>", opts)
      vim.api.nvim_set_keymap("v", "<leader>zf", ":'<,'>ZkMatch<CR>", opts)
      -- vim.api.nvim_set_keymap("v", "<leader>zt", ":lua zk_wrapper('ZkNewFromTitleSelection')", opts)
      -- vim.api.nvim_set_keymap("v", "<leader>zc", ":lua zk_wrapper('ZkNewFromContentSelection')", opts)
    end,
  },
}
