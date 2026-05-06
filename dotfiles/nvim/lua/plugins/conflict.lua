return {
  "rhysd/conflict-marker.vim",
  lazy = false,
  config = function()
    vim.g.conflict_marker_begin = "^<<<<<<< .*$"
    vim.g.conflict_marker_end = "^>>>>>>> .*$"
    -- disable the default highlight group
    vim.g.conflict_marker_highlight_group = ""
    vim.cmd "hi ConflictMarkerBegin guibg=#2f7366"
    vim.cmd "hi ConflictMarkerOurs guibg=#2e5049"
    vim.cmd "hi ConflictMarkerTheirs guibg=#344f69"
    vim.cmd "hi ConflictMarkerEnd guibg=#2f628e"
    vim.cmd "hi ConflictMarkerCommonAncestorsHunk guibg=#754a81"
  end,
}
