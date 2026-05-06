-- AstroLSP allows you to customize the features in AstroNvim's LSP configuration engine
-- Configuration documentation can be found with `:h astrolsp`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = function(plugin, opts)
    -- insert "prolog_lsp" into our list of servers
    -- opts.servers = opts.servers or {}
    -- table.insert(opts.servers, "ciderlsp")
    --
    -- -- extend our configuration table to have our new prolog server
    -- opts.config = require("astrocore").extend_tbl(opts.config or {}, {
    --   -- this must be a function to get access to the `lspconfig` module
    --   ciderlsp = {
    --     -- the command for starting the server
    --     cmd = {
    --       "/google/bin/releases/cider/ciderlsp/ciderlsp",
    --       "--tooltag=nvim-lsp",
    --       "--noforward_sync_responses",
    --       "--request_options=" .. table.concat(ciderlsp_settings, ","),
    --     },
    --     filetypes = {
    --       "c",
    --       "cpp",
    --       "java",
    --       "kotlin",
    --       "objc",
    --       "proto",
    --       "gcl",
    --       "yaml",
    --       "textpb",
    --       "go",
    --       "python",
    --       "bzl",
    --       "typescript",
    --       "sql",
    --       "txt",
    --     },
    --     offset_encoding = "utf-8",
    --     -- root directory detection for detecting the project root
    --     root_dir = require("lspconfig.util").root_pattern ".citc",
    --   },
    --   lua_ls = {
    --     on_attach = function(client)
    --       -- Disable semantic tokens so Treesitter (Markdown) takes priority
    --       client.server_capabilities.semanticTokensProvider = nil
    --     end,
    --   },
    -- })
  end,
}
