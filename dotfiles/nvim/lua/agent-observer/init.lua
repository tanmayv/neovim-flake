local M = {}

M.config = {
  vcs_adapter = "git", -- default
  expand_level = 2, -- default expand level
  show_hidden = false, -- default show hidden files
}

M.active_session_files = {}
M.buf_id = nil
M.win_id = nil
M.main_win_id = nil
M.watcher = nil
M.tab_id = nil
M.tree = nil
M.auto_mode = true

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
M.file_state = {} -- path -> { opened = bool, deleted = bool }

function M.update_vcs_state()
  -- Check if in git repo first
  local handle = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null")
  local is_git = handle:read("*l")
  handle:close()
  
  if is_git ~= "true" then
    return
  end

  -- Async git status
  vim.system({ "git", "status", "--porcelain" }, { text = true }, function(obj)
    if obj.code == 0 then
      local result = {}
      for line in vim.gsplit(obj.stdout, "\n") do
        if #line > 3 then
          local status = line:sub(1, 2)
          local file = line:sub(4)
          table.insert(result, file)
          M.file_state[file] = M.file_state[file] or {}
          M.file_state[file].vcs_status = status
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

function M.get_base_content(file, callback)
  -- Check if in git repo first
  local handle = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null")
  local is_git = handle:read("*l")
  handle:close()
  
  if is_git ~= "true" then
    return
  end

  local cmd = { "git", "show", "HEAD:" .. file }
  
  vim.system(cmd, { text = true }, function(obj)
    if obj.code == 0 then
      callback(obj.stdout)
    else
      vim.schedule(function()
        vim.notify("Failed to get base content: " .. obj.stderr, vim.log.levels.ERROR)
      end)
    end
  end)
end

local function get_dir_and_file(path)
  local parts = vim.split(path, "/")
  if #parts == 1 then
    return "./", parts[1]
  else
    local file = table.remove(parts)
    return table.concat(parts, "/") .. "/", file
  end
end

local function build_tree_nodes(files, category)
  local NuiTree = require("nui.tree")
  local dir_groups = {}
  
  for _, file in ipairs(files) do
    if M.config.show_hidden or not file:match("^%.") then
      local dir, filename = get_dir_and_file(file)
      if not dir_groups[dir] then
        dir_groups[dir] = {}
      end
      table.insert(dir_groups[dir], { filename = filename, full_path = file })
    end
  end
  
  local nodes = {}
  local dirs = vim.tbl_keys(dir_groups)
  table.sort(dirs)
  
  for _, dir in ipairs(dirs) do
    local file_infos = dir_groups[dir]
    table.sort(file_infos, function(a, b) return a.filename < b.filename end)
    
    local file_nodes = {}
    for _, info in ipairs(file_infos) do
      local state = M.file_state[info.full_path] or { opened = false, deleted = false }
      table.insert(file_nodes, NuiTree.Node({
        text = info.filename,
        is_file = true,
        path = info.full_path,
        category = category,
        opened = state.opened,
        deleted = state.deleted
      }))
    end
    
    table.insert(nodes, NuiTree.Node({
      text = dir,
      is_file = false,
      category = category,
      _is_expanded = true
    }, file_nodes))
  end
  return nodes
end

function M.render_ui()
  if not M.buf_id or not vim.api.nvim_buf_is_valid(M.buf_id) then
    return
  end

  local NuiTree = require("nui.tree")

  local root_nodes = {}

  -- Auto Mode Status
  local status_text = M.auto_mode and " [Auto Mode: ON]" or " [Auto Mode: OFF]"
  table.insert(root_nodes, NuiTree.Node({ text = status_text, is_status = true }))

  -- Active Session
  local active_node = NuiTree.Node({ text = "Active Session", is_category = true, _is_expanded = true }, build_tree_nodes(M.active_session_files, "active"))
  table.insert(root_nodes, active_node)

  -- Pending Changes
  local pending_node = NuiTree.Node({ text = "Pending Changes", is_category = true, _is_expanded = true }, build_tree_nodes(M.pending_files, "pending"))
  table.insert(root_nodes, pending_node)

  -- Last Commit
  local last_node = NuiTree.Node({ text = "Last Commit", is_category = true, _is_expanded = true }, build_tree_nodes(M.last_commit_files, "last"))
  table.insert(root_nodes, last_node)

  if not M.tree then
    M.tree = NuiTree({
      bufnr = M.buf_id,
      nodes = root_nodes,
      prepare_node = function(node)
        local NuiLine = require("nui.line")
        local line = NuiLine()
        if node.is_status then
          line:append(node.text, "Keyword")
        elseif node.is_category then
          line:append(" " .. node.text, "Title")
        elseif not node.is_file then
          line:append("  " .. node.text, "Directory")
        else
          local hl = "Normal"
          if node.deleted then
            hl = "DiagnosticError" -- Red
          elseif node.category == "active" and not node.opened then
            hl = "DiagnosticOk" -- Green (or String if DiagnosticOk not available)
          end
          line:append("    " .. node.text, hl)
        end
        return line
      end,
    })
  else
    M.tree:set_nodes(root_nodes)
  end

  -- Force expand all nodes
  for _, node in pairs(M.tree.nodes.by_id) do
    node:expand()
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
        
        local full_path = path .. "/" .. filename
        local stat = uv.fs_stat(full_path)
        local is_dir = stat and stat.type == "directory"
        local deleted = not stat

        M.file_state[filename] = { opened = false, deleted = deleted }

        if not found and not is_dir then
          table.insert(M.active_session_files, 1, filename) -- prepend
        end
        -- Fetch fresh git status and last commit asynchronously
        M.update_vcs_state()

        if M.auto_mode and not is_dir then
          M.open_diff(filename, true)
        end

        -- Check if the file is open in any buffer and reload it
        local full_path = path .. "/" .. filename
        local bufnr = vim.fn.bufnr(full_path)
        if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
          vim.cmd("checktime " .. bufnr)
        end
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

function M.open_diff(file, keep_focus)
  local state = M.file_state[file]
  if state and (state.vcs_status == "??" or state.vcs_status == "A ") then
    vim.schedule(function()
      -- Close other windows in the tab
      local current_tab = vim.api.nvim_get_current_tabpage()
      local wins = vim.api.nvim_tabpage_list_wins(current_tab)
      for _, w in ipairs(wins) do
        if w ~= M.win_id then
          pcall(vim.api.nvim_win_close, w, true)
        end
      end

      -- Now only M.win_id is left, it fills the screen.
      -- We want to restore it to width 35 on the right.
      -- So we create a new window on the left.
      vim.api.nvim_set_current_win(M.win_id)
      vim.cmd("leftabove vsplit")
      local working_win = vim.api.nvim_get_current_win()
      M.main_win_id = working_win
      
      -- Set width of observer back to 35
      vim.api.nvim_win_set_width(M.win_id, 35)

      -- Now set up file in working_win
      vim.api.nvim_set_current_win(working_win)
      vim.cmd("edit " .. file)
      
      vim.bo.readonly = true
      vim.bo.modifiable = false
      
      -- Stay in working window or return to observer
      if keep_focus then
        vim.api.nvim_set_current_win(M.win_id)
      else
        vim.api.nvim_set_current_win(working_win)
      end
    end)
    return
  end

  M.get_base_content(file, function(base_content)
    vim.schedule(function()
      -- Close other windows in the tab
      local current_tab = vim.api.nvim_get_current_tabpage()
      local wins = vim.api.nvim_tabpage_list_wins(current_tab)
      for _, w in ipairs(wins) do
        if w ~= M.win_id then
          pcall(vim.api.nvim_win_close, w, true)
        end
      end

      -- Now only M.win_id is left, it fills the screen.
      -- We want to restore it to width 35 on the right.
      -- So we create a new window on the left.
      vim.api.nvim_set_current_win(M.win_id)
      vim.cmd("leftabove vsplit")
      local working_win = vim.api.nvim_get_current_win()
      
      -- Set width of observer back to 35
      vim.api.nvim_win_set_width(M.win_id, 35)

      -- Now set up diff in working_win
      vim.api.nvim_set_current_win(working_win)
      vim.cmd("edit " .. file)
      
      local working_buf = vim.api.nvim_get_current_buf()
      
      -- Create split for base file
      vim.cmd("vsplit")
      local base_win = vim.api.nvim_get_current_win()
      local base_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(base_win, base_buf)
      
      -- Set base content
      local lines = vim.split(base_content, "\n")
      vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, lines)
      
      -- Set filetype for syntax highlighting
      local ft = vim.filetype.match({ filename = file })
      if ft then
        vim.api.nvim_buf_set_option(base_buf, "filetype", ft)
      end
      
      vim.bo[base_buf].readonly = true
      vim.bo[base_buf].modifiable = false
      
      -- Diff this!
      vim.api.nvim_set_current_win(working_win)
      vim.cmd("diffthis")
      vim.api.nvim_set_current_win(base_win)
      vim.cmd("diffthis")
      
      -- Stay in working window or return to observer
      if keep_focus then
        vim.api.nvim_set_current_win(M.win_id)
      else
        vim.api.nvim_set_current_win(working_win)
      end
    end)
  end)
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
  M.show_startup_help()

  M.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf_id, "filetype", "agent-observer")

  vim.cmd("botright 35vsplit")
  M.win_id = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win_id, M.buf_id)

  M.update_vcs_state()

  local opts = { buffer = M.buf_id, noremap = true, silent = true }
  
  local function open_file(mode, keep_focus)
    local node = M.tree:get_node()
    if node and node.is_file and node.path then
      if node.deleted then
        M.open_diff(node.path, keep_focus)
        return
      end

      -- Mark as opened
      M.file_state[node.path] = M.file_state[node.path] or {}
      M.file_state[node.path].opened = true
      M.render_ui()

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
      
      if keep_focus then
        vim.api.nvim_set_current_win(M.win_id)
      end
    end
  end

  -- o to open in main pane and keep focus
  vim.keymap.set("n", "o", function() open_file("edit", true) end, opts)
  
  -- Enter to open in main pane and move focus
  vim.keymap.set("n", "<CR>", function() open_file("edit", false) end, opts)

  -- s to open in horizontal split and move focus
  vim.keymap.set("n", "s", function() open_file("split", false) end, opts)

  -- v to open in vertical split and move focus
  vim.keymap.set("n", "v", function() open_file("vsplit", false) end, opts)

  -- d to open diff and keep focus
  vim.keymap.set("n", "d", function()
    local node = M.tree:get_node()
    if node and node.is_file and node.path then
      M.open_diff(node.path, true)
    end
  end, opts)

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

  -- h to toggle hidden files
  vim.keymap.set("n", "h", function()
    M.config.show_hidden = not M.config.show_hidden
    M.render_ui()
  end, opts)

  -- a to toggle auto mode
  vim.keymap.set("n", "a", function()
    M.auto_mode = not M.auto_mode
    M.render_ui()
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


function M.show_startup_help()
  local lines = {
    "# Agent Observer",
    "",
    "The Agent Observer monitors file changes made by background agents in real-time.",
    "",
    "## Keybindings",
    "",
    "| Key | Action | Focus |",
    "| --- | --- | --- |",
    "| `o` | Open file in main pane | Stays on Observer |",
    "| `<CR>` | Open file in main pane | Moves to file |",
    "| `s` | Open file in horizontal split | Moves to split |",
    "| `v` | Open file in vertical split | Moves to split |",
    "| `d` | Open diff against HEAD | Stays on Observer |",
    "| `l` | Expand/Collapse tree node | - |",
    "| `h` | Toggle hidden files | - |",
    "| `a` | Toggle auto mode | - |",
    "| `q` | Close Observer tab | - |",
    "",
    "Files in **Active Session** are color coded:",
    "- **Green**: Changed but not yet opened.",
    "- **Red**: Deleted (cannot be opened, but supports diff).",
  }

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]

  if buf_name == "" and line_count == 1 and first_line == "" then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  vim.api.nvim_create_user_command("AgentObserverToggle", function()
    M.toggle_diff()
  end, {})

  M.start_watcher()
  M.update_vcs_state()
end

return M
