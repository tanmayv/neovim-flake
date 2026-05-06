local M = {}

M.config = {
  vcs_adapter = "git", -- default
}

M.active_session_files = {}
M.buf_id = nil
M.win_id = nil
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

local function update_vcs_state()
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

-- Helper to build tree nodes from paths
local function add_path_to_tree(root_nodes, path, category)
  local NuiNode = require("nui.tree.node")
  local parts = vim.split(path, "/")
  local current_level = root_nodes

  for i, part in ipairs(parts) do
    local is_file = (i == #parts)
    local found = false
    for _, node in ipairs(current_level) do
      if node.text == part and not node.is_file then
        current_level = node:get_children()
        found = true
        break
      end
    end

    if not found then
      local new_node = NuiNode({
        text = part,
        is_file = is_file,
        path = path,
        category = category
      })
      table.insert(current_level, new_node)
      if not is_file then
        current_level = new_node:get_children()
      end
    end
  end
end

function M.render_ui()
  if not M.buf_id or not vim.api.nvim_buf_is_valid(M.buf_id) then
    return
  end

  local NuiTree = require("nui.tree")
  local NuiNode = require("nui.tree.node")

  local root_nodes = {}

  -- Active Session
  local active_node = NuiNode({ text = "Active Session", is_category = true })
  local active_children = {}
  for _, file in ipairs(M.active_session_files) do
    add_path_to_tree(active_children, file, "active")
  end
  for _, child in ipairs(active_children) do
    active_node:append(child)
  end
  table.insert(root_nodes, active_node)

  -- Pending Changes
  local pending_node = NuiNode({ text = "Pending Changes", is_category = true })
  local pending_children = {}
  for _, file in ipairs(M.pending_files) do
    add_path_to_tree(pending_children, file, "pending")
  end
  for _, child in ipairs(pending_children) do
    pending_node:append(child)
  end
  table.insert(root_nodes, pending_node)

  -- Last Commit
  local last_node = NuiNode({ text = "Last Commit", is_category = true })
  local last_children = {}
  for _, file in ipairs(M.last_commit_files) do
    add_path_to_tree(last_children, file, "last")
  end
  for _, child in ipairs(last_children) do
    last_node:append(child)
  end
  table.insert(root_nodes, last_node)

  if not M.tree then
    M.tree = NuiTree({
      nodes = root_nodes,
      prepare_node = function(node)
        local text = node.text
        if node.is_category then
          text = " " .. text
        elseif not node.is_file then
          text = "  " .. text .. "/"
        else
          text = "    " .. text
        end
        return text
      end,
    })
  else
    M.tree:set_nodes(root_nodes)
  end

  M.tree:render(M.buf_id)
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
        update_vcs_state()
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

  M.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf_id, "filetype", "agent-observer")

  vim.cmd("botright 40vsplit")
  M.win_id = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win_id, M.buf_id)

  update_vcs_state()

  local opts = { buffer = M.buf_id, noremap = true, silent = true }
  
  local function open_file(mode)
    local node = M.tree:get_node()
    if node and node.is_file and node.path then
      vim.cmd("wincmd h")
      if mode == "edit" then
        vim.cmd("edit " .. node.path)
      elseif mode == "split" then
        vim.cmd("split " .. node.path)
      elseif mode == "vsplit" then
        vim.cmd("vsplit " .. node.path)
      end
      vim.bo.readonly = true
      vim.bo.modifiable = false
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
      node:toggle()
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
