---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  tag = "v0.9.3",
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
