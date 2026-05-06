local M = {}

M.config = {
  vcs_adapter = "git", -- default
  expand_level = 2, -- default expand level
}

M.active_session_files = {}
M.buf_id = nil
M.win_id = nil
M.main_win_id = nil
M.watcher = nil
M.tab_id = nil
M.tree = nil

-- Helper to get git root
local function get_git_root()
  local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
  if not handle then return nil end
  local result = handle:read("*l")
  handle:close()
  return result
end

M.pending_files = {}
M.last_commit_files = {}

function M.update_vcs_state()
  -- Async git status
  vim.system({ "git", "status", "--porcelain" }, { text = true }, function(obj)
    if obj.code == 0 then
      local result = {}
      for line in vim.gsplit(obj.stdout, "\n") do
        local file = line:match("^%s*%S+%s+(.+)")
        if file then
          table.insert(result, file)
        end
      end
      M.pending_files = result
      vim.schedule(function()
        M.render_ui()
      end)
    end
  end)

  -- Async git last commit
  vim.system({ "git", "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD" }, { text = true }, function(obj)
    if obj.code == 0 then
      local result = {}
      for line in vim.gsplit(obj.stdout, "\n") do
        if line ~= "" then
          table.insert(result, line)
        end
      end
      M.last_commit_files = result
      vim.schedule(function()
        M.render_ui()
      end)
    end
  end)
end

-- Helper to build tree table from paths
local function add_to_table(tbl, path_parts, full_path, category)
  local current = tbl
  for i, part in ipairs(path_parts) do
    local is_file = (i == #path_parts)
    if not current[part] then
      current[part] = {
        text = part,
        is_file = is_file,
        path = is_file and full_path or nil,
        category = category,
        children = {}
      }
    end
    current = current[part].children
  end
end

-- Helper to convert table to NuiTree nodes
local function convert_to_nui_nodes(tbl)
  local NuiTree = require("nui.tree")
  local nodes = {}
  local keys = vim.tbl_keys(tbl)
  table.sort(keys)
  
  for _, key in ipairs(keys) do
    local data = tbl[key]
    local children = convert_to_nui_nodes(data.children)
    table.insert(nodes, NuiTree.Node({
      text = data.text,
      is_file = data.is_file,
      path = data.path,
      category = data.category,
      _is_expanded = not data.is_file
    }, #children > 0 and children or nil))
  end
  return nodes
end

function M.render_ui()
  if not M.buf_id or not vim.api.nvim_buf_is_valid(M.buf_id) then
    return
  end

  local NuiTree = require("nui.tree")

  local root_nodes = {}

  -- Active Session
  local active_table = {}
  for _, file in ipairs(M.active_session_files) do
    add_to_table(active_table, vim.split(file, "/"), file, "active")
  end
  local active_node = NuiTree.Node({ text = "Active Session", is_category = true, _is_expanded = true }, convert_to_nui_nodes(active_table))
  table.insert(root_nodes, active_node)

  -- Pending Changes
  local pending_table = {}
  for _, file in ipairs(M.pending_files) do
    add_to_table(pending_table, vim.split(file, "/"), file, "pending")
  end
  local pending_node = NuiTree.Node({ text = "Pending Changes", is_category = true, _is_expanded = true }, convert_to_nui_nodes(pending_table))
  table.insert(root_nodes, pending_node)

  -- Last Commit
  local last_table = {}
  for _, file in ipairs(M.last_commit_files) do
    add_to_table(last_table, vim.split(file, "/"), file, "last")
  end
  local last_node = NuiTree.Node({ text = "Last Commit", is_category = true, _is_expanded = true }, convert_to_nui_nodes(last_table))
  table.insert(root_nodes, last_node)

  if not M.tree then
    M.tree = NuiTree({
      bufnr = M.buf_id,
      nodes = root_nodes,
      prepare_node = function(node)
        local NuiLine = require("nui.line")
        local line = NuiLine()
        if node.is_category then
          line:append(" " .. node.text, "Title")
        elseif not node.is_file then
          line:append("  " .. node.text .. "/", "Directory")
        else
          line:append("    " .. node.text, "Normal")
        end
        return line
      end,
    })
  else
    M.tree:set_nodes(root_nodes)
  end

  -- Expand to configured level
  for _, node in pairs(M.tree.nodes.by_id) do
    if node:get_depth() <= M.config.expand_level and not node.is_file then
      node:expand()
    end
  end

  M.tree:render()
end

function M.start_watcher()
  if M.watcher then return end

  local uv = vim.uv or vim.loop
  M.watcher = uv.new_fs_event()
  
  local path = vim.fn.getcwd()
  
  M.watcher:start(path, { recursive = true }, function(err, filename, events)
    if err then
      vim.schedule(function()
        vim.notify("Observer error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    if filename and not filename:match("^%.git/") then
      vim.schedule(function()
        -- Add to active session if not already there
        local found = false
        for _, f in ipairs(M.active_session_files) do
          if f == filename then
            found = true
            break
          end
        end
        if not found then
          table.insert(M.active_session_files, 1, filename) -- prepend
        end
        -- Fetch fresh git status and last commit asynchronously
        M.update_vcs_state()
      end)
    end
  end)
end

function M.stop_watcher()
  if M.watcher then
    M.watcher:stop()
    M.watcher = nil
  end
end

function M.toggle_diff()
  if M.tab_id and vim.api.nvim_tabpage_is_valid(M.tab_id) then
    vim.api.nvim_set_current_tabpage(M.tab_id)
    vim.cmd("tabclose")
    M.tab_id = nil
    M.win_id = nil
    M.buf_id = nil
    M.tree = nil
    return
  end

  vim.cmd("tabnew")
  M.tab_id = vim.api.nvim_get_current_tabpage()
  M.main_win_id = vim.api.nvim_get_current_win()

  M.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf_id, "filetype", "agent-observer")

  vim.cmd("botright 40vsplit")
  M.win_id = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win_id, M.buf_id)

  M.update_vcs_state()

  local opts = { buffer = M.buf_id, noremap = true, silent = true }
  
  local function open_file(mode)
    local node = M.tree:get_node()
    if node and node.is_file and node.path then
      local target_win = M.main_win_id
      
      if not target_win or not vim.api.nvim_win_is_valid(target_win) then
        local current_tab = vim.api.nvim_get_current_tabpage()
        local wins = vim.api.nvim_tabpage_list_wins(current_tab)
        for _, w in ipairs(wins) do
          if w ~= M.win_id then
            target_win = w
            break
          end
        end
      end

      if not target_win or not vim.api.nvim_win_is_valid(target_win) then
        vim.cmd("leftabove vsplit")
        target_win = vim.api.nvim_get_current_win()
        M.main_win_id = target_win
      end

      vim.api.nvim_set_current_win(target_win)

      if mode == "edit" then
        vim.cmd("edit " .. node.path)
      elseif mode == "split" then
        vim.cmd("split " .. node.path)
      elseif mode == "vsplit" then
        vim.cmd("vsplit " .. node.path)
      end
      
      vim.bo.readonly = true
      vim.bo.modifiable = false
      
      if mode == "edit" then
        vim.api.nvim_set_current_win(M.win_id)
      end
    end
  end

  -- o or Enter to open in main pane
  vim.keymap.set("n", "o", function() open_file("edit") end, opts)
  vim.keymap.set("n", "<CR>", function() open_file("edit") end, opts)

  -- s to open in horizontal split
  vim.keymap.set("n", "s", function() open_file("split") end, opts)

  -- v to open in vertical split
  vim.keymap.set("n", "v", function() open_file("vsplit") end, opts)

  -- l to expand/collapse
  vim.keymap.set("n", "l", function()
    local node = M.tree:get_node()
    if node and not node.is_file then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      M.tree:render()
    end
  end, opts)

  -- q to close
  vim.keymap.set("n", "q", function()
    vim.cmd("tabclose")
    M.tab_id = nil
    M.win_id = nil
    M.buf_id = nil
    M.tree = nil
  end, opts)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  vim.api.nvim_create_user_command("AgentObserverToggle", function()
    M.toggle_diff()
  end, {})

  M.start_watcher()
end

return M
