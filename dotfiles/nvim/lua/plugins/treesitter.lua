---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "c",
      "cpp",
      "starlark",
      "textproto",
      "sql",
      "yaml",
      -- add more arguments for adding more treesitter parsers
    },
    highlight = {
      enable = true,
    },
  },
}
