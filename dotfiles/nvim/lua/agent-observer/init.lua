local M = {}

M.config = {
  vcs_adapter = "git", -- default
  expand_level = 2, -- default expand level
  show_hidden = false, -- default show hidden files
  poll_interval = 60, -- default polling interval in seconds
  track_hidden = false, -- default: do not track hidden directories
}

M.active_session_files = {}
M.buf_id = nil
M.win_id = nil
M.main_win_id = nil
M.watchers = {}
M.watched_paths = {}
M.base_dir = nil
M.git_root = nil
M.tab_id = nil
M.tree = nil
M.auto_mode = true
M.loading_pending = false
M.loading_last = false
M.loading_diff_file = nil
M.seconds_to_update = 60
M.poll_timer = nil

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

function M.reset_base_dir()
  local new_cwd = vim.fn.getcwd()
  if new_cwd == M.base_dir then
    vim.notify("Base directory is already synced to CWD", vim.log.levels.INFO)
    return
  end

  -- Check if inside git repo
  local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
  local git_root = handle and handle:read("*l")
  if handle then handle:close() end

  if not git_root then
    vim.notify("Cannot sync base directory: " .. new_cwd .. " is not inside a Git repository.", vim.log.levels.ERROR)
    return
  end

  M.git_root = git_root
  M.base_dir = new_cwd
  
  vim.notify("Synced Agent Observer base to: " .. M.base_dir, vim.log.levels.INFO)

  M.stop_watcher()
  M.active_session_files = {}
  M.file_state = {}
  M.start_watcher()
  M.update_vcs_state()
end

function M.update_vcs_state()
  if not M.git_root then
    M.pending_files = {}
    M.last_commit_files = {}
    vim.schedule(function()
      M.render_ui()
    end)
    return
  end

  M.loading_pending = true
  M.loading_last = true
  M.render_ui()

  -- Async git status
  vim.system({ "git", "status", "--porcelain", "-u" }, { text = true, cwd = M.base_dir }, function(obj)
    M.loading_pending = false
    if obj.code == 0 then
      local result = {}
      for line in vim.gsplit(obj.stdout, "\n") do
        if #line > 3 then
          local status = line:sub(1, 2)
          local file = line:sub(4)
          local abs_path = M.git_root .. "/" .. file
          -- Filter by base_dir and skip directories (paths ending with /)
          if not file:match("/$") and abs_path:sub(1, #M.base_dir) == M.base_dir then
            table.insert(result, abs_path)
            M.file_state[abs_path] = M.file_state[abs_path] or {}
            M.file_state[abs_path].vcs_status = status
          end
        end
      end
      M.pending_files = result
      vim.schedule(function()
        M.render_ui()
      end)
    else
      vim.schedule(function()
        M.render_ui()
      end)
    end
  end)

  -- Async git last commit
  vim.system({ "git", "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD" }, { text = true, cwd = M.base_dir }, function(obj)
    M.loading_last = false
    if obj.code == 0 then
      local result = {}
      for line in vim.gsplit(obj.stdout, "\n") do
        if line ~= "" then
          local abs_path = M.git_root .. "/" .. line
          if abs_path:sub(1, #M.base_dir) == M.base_dir then
            table.insert(result, abs_path)
          end
        end
      end
      M.last_commit_files = result
      vim.schedule(function()
        M.render_ui()
      end)
    else
      vim.schedule(function()
        M.render_ui()
      end)
    end
  end)
end

function M.get_base_content(file, callback)
  if not M.git_root then
    return
  end

  local rel_path = file
  if file:sub(1, #M.git_root) == M.git_root then
    rel_path = file:sub(#M.git_root + 2)
  end

  local cmd = { "git", "show", "HEAD:" .. rel_path }
  
  vim.system(cmd, { text = true, cwd = M.base_dir }, function(obj)
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

local function get_directories(dir, dirs)
  dirs = dirs or {}
  local uv = vim.uv or vim.loop
  local handle = uv.fs_scandir(dir)
  if not handle then return dirs end

  while true do
    local name, type = uv.fs_scandir_next(handle)
    if not name then break end
    if type == "directory" and name ~= ".git" then
      local is_hidden = name:match("^%.")
      if M.config.track_hidden or not is_hidden then
        local path = dir .. "/" .. name
        table.insert(dirs, path)
        get_directories(path, dirs)
      end
    end
  end
  return dirs
end


local function build_tree_nodes(files, category)
  local NuiTree = require("nui.tree")
  local dir_groups = {}
  
  for _, file in ipairs(files) do
    local rel_path = file
    if M.base_dir and file:sub(1, #M.base_dir) == M.base_dir then
      rel_path = file:sub(#M.base_dir + 2)
    end

    -- Use rel_path to check if hidden (at the base_dir level)
    if M.config.show_hidden or not rel_path:match("^%.") then
      local dir, filename = get_dir_and_file(rel_path)
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

  -- CWD vs Base Dir Status
  local cwd = vim.fn.getcwd()
  local base_display = M.base_dir or "nil"
  local home = os.getenv("HOME")
  if home then
    if base_display:sub(1, #home) == home then
      base_display = "~" .. base_display:sub(#home + 1)
    end
  end

  local status_text = M.auto_mode and " 🟢 Auto" or " 🔴 Manual"
  status_text = status_text .. " | Base: " .. base_display
  if M.loading_pending or M.loading_last then
    status_text = status_text .. " ⏳"
  else
    status_text = status_text .. " [" .. M.seconds_to_update .. "s]"
  end
  table.insert(root_nodes, NuiTree.Node({ text = status_text, is_status = true }))

  if cwd ~= M.base_dir then
    local cwd_display = cwd
    if home and cwd_display:sub(1, #home) == home then
      cwd_display = "~" .. cwd_display:sub(#home + 1)
    end
    table.insert(root_nodes, NuiTree.Node({ 
      text = " ⚠️ CWD changed to: " .. cwd_display .. " (Press 'C' to sync)", 
      is_status = true,
      is_warning = true 
    }))
  end

  -- Active Session
  local active_node = NuiTree.Node({ text = "Active Session", is_category = true, category_type = "active", _is_expanded = true }, build_tree_nodes(M.active_session_files, "active"))
  table.insert(root_nodes, active_node)

  -- Pending Changes
  local pending_node = NuiTree.Node({ text = "Pending Changes", is_category = true, category_type = "pending", _is_expanded = true }, build_tree_nodes(M.pending_files, "pending"))
  table.insert(root_nodes, pending_node)

  -- Last Commit
  local last_node = NuiTree.Node({ text = "Last Commit", is_category = true, category_type = "last", _is_expanded = true }, build_tree_nodes(M.last_commit_files, "last"))
  table.insert(root_nodes, last_node)

  -- Watched Paths (Debug)
  local watched_nodes = {}
  if M.watched_paths and #M.watched_paths > 0 then
    for _, path in ipairs(M.watched_paths) do
      table.insert(watched_nodes, NuiTree.Node({ text = path, is_file = true }))
    end
  else
    table.insert(watched_nodes, NuiTree.Node({ text = "No paths being watched", is_file = true }))
  end
  local watched_node = NuiTree.Node({ text = "Watched Paths (Debug)", is_category = true, category_type = "debug", _is_expanded = true }, watched_nodes)
  table.insert(root_nodes, watched_node)

  if not M.tree then
    M.tree = NuiTree({
      bufnr = M.buf_id,
      nodes = root_nodes,
      prepare_node = function(node)
        local NuiLine = require("nui.line")
        local line = NuiLine()
        if node.is_status then
          local hl = "Keyword"
          if node.is_warning then
            hl = "DiagnosticWarn"
          end
          line:append(node.text, hl)
        elseif node.is_category then
          local hl = "Title"
          if node.category_type == "active" then
            hl = "DiagnosticInfo"
          elseif node.category_type == "pending" then
            hl = "DiagnosticWarn"
          elseif node.category_type == "last" then
            hl = "DiagnosticHint"
          elseif node.category_type == "debug" then
            hl = "Comment"
          end
          line:append(" " .. node.text, hl)
        elseif not node.is_file then
          line:append("  " .. node.text, "Directory")
        else
          local hl = "Normal"
          if node.deleted then
            hl = "DiagnosticError" -- Red
          elseif node.category == "active" and not node.opened then
            hl = "DiagnosticOk" -- Green (or String if DiagnosticOk not available)
          end
          local text = node.text
          if node.path == M.loading_diff_file then
            text = text .. " ⏳"
          end
          line:append("    " .. text, hl)
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

local function watch_dir(dir_path)
  if M.watchers[dir_path] then return end

  local uv = vim.uv or vim.loop
  local watcher = uv.new_fs_event()
  
  watcher:start(dir_path, {}, function(err, filename, events)
    if err then
      vim.schedule(function()
        vim.notify("Observer error on " .. dir_path .. ": " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    
    if filename then
      local full_path = dir_path .. "/" .. filename
      if full_path:match("/%.git/") then return end

      vim.schedule(function()
        local stat = uv.fs_stat(full_path)
        local is_dir = stat and stat.type == "directory"
        local deleted = not stat

        -- Handle deleted watched directory
        if M.watchers[full_path] and deleted then
          M.watchers[full_path]:stop()
          if not M.watchers[full_path]:is_closing() then
            M.watchers[full_path]:close()
          end
          M.watchers[full_path] = nil
          M.watched_paths = vim.tbl_keys(M.watchers)
          table.sort(M.watched_paths)
          M.render_ui()
          return
        end

        if is_dir and not deleted then
          local is_hidden = filename:match("^%.")
          if filename ~= ".git" and (M.config.track_hidden or not is_hidden) then
            watch_dir(full_path)
            M.watched_paths = vim.tbl_keys(M.watchers)
            table.sort(M.watched_paths)
            M.render_ui()
          end
          return
        end

        M.file_state[full_path] = { opened = false, deleted = deleted }

        local found = false
        for _, f in ipairs(M.active_session_files) do
          if f == full_path then
            found = true
            break
          end
        end

        if not found and not is_dir then
          table.insert(M.active_session_files, 1, full_path)
        end

        M.update_vcs_state()

        if M.auto_mode and not is_dir and not deleted then
          M.open_diff(full_path, true)
        end

        local bufnr = vim.fn.bufnr(full_path)
        if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
          vim.cmd("checktime " .. bufnr)
        end
      end)
    end
  end)

  M.watchers[dir_path] = watcher
end

function M.start_watcher()
  M.watchers = M.watchers or {}
  local base = M.base_dir or vim.fn.getcwd()
  M.base_dir = base
  watch_dir(base)
  
  local dirs = get_directories(base)
  for _, dir in ipairs(dirs) do
    watch_dir(dir)
  end

  M.watched_paths = vim.tbl_keys(M.watchers)
  table.sort(M.watched_paths)
  vim.schedule(function()
    M.render_ui()
  end)
end

function M.stop_watcher()
  if M.watchers then
    for path, watcher in pairs(M.watchers) do
      watcher:stop()
      if not watcher:is_closing() then
        watcher:close()
      end
    end
  end
  M.watchers = {}
  M.watched_paths = {}
end

function M.open_diff(file, keep_focus)
  if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then
    return
  end

  -- Guard against directories
  if vim.fn.isdirectory(file) == 1 or file:match("/$") then
    return
  end

  local state = M.file_state[file]
  local status = state and state.vcs_status or ""
  status = vim.trim(status)
  
  if status == "??" or status == "?" or status == "A" then
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

  M.loading_diff_file = file
  M.render_ui()

  M.get_base_content(file, function(base_content)
    vim.schedule(function()
      -- Verify window is still valid
      if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then
        M.loading_diff_file = nil
        return
      end

      M.loading_diff_file = nil
      M.render_ui()
      
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

  -- Disable line numbers and signs to save space
  vim.wo[M.win_id].number = false
  vim.wo[M.win_id].relativenumber = false
  vim.wo[M.win_id].signcolumn = "no"
  vim.wo[M.win_id].foldcolumn = "0"

  M.update_vcs_state()

  local opts = { buffer = M.buf_id, noremap = true, silent = true }
  
  local function open_file(mode, keep_focus)
    local node = M.tree:get_node()
    if node and node.is_file and node.path then
      -- Guard against directories
      if vim.fn.isdirectory(node.path) == 1 or node.path:match("/$") then
        return
      end

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
  
  -- C to sync base dir to current CWD
  vim.keymap.set("n", "C", function()
    M.reset_base_dir()
  end, opts)
  
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

  -- r to manually refresh
  vim.keymap.set("n", "r", function()
    M.update_vcs_state()
    M.seconds_to_update = 60
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
    "| `r` | Manual refresh | - |",
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
  
  -- Clean up existing timer if setup is called again
  if M.poll_timer then
    M.poll_timer:stop()
    if not M.poll_timer:is_closing() then
      M.poll_timer:close()
    end
    M.poll_timer = nil
  end

  vim.api.nvim_create_user_command("AgentObserverToggle", function()
    M.toggle_diff()
  end, {})

  M.base_dir = vim.fn.getcwd()
  M.git_root = get_git_root()

  M.start_watcher()
  M.update_vcs_state()

  M.seconds_to_update = M.config.poll_interval

  -- Start polling timer
  local uv = vim.uv or vim.loop
  M.poll_timer = uv.new_timer()
  M.poll_timer:start(1000, 1000, vim.schedule_wrap(function()
    M.seconds_to_update = M.seconds_to_update - 1
    if M.seconds_to_update <= 0 then
      M.update_vcs_state()
      M.seconds_to_update = M.config.poll_interval
    else
      M.render_ui()
    end
  end))
end

return M
