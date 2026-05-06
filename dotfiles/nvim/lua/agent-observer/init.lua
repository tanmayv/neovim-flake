local M = {}

M.config = {
  vcs_adapter = "git", -- default
}

M.active_session_files = {}
M.buf_id = nil
M.win_id = nil
M.watcher = nil

local function get_git_status()
  local handle = io.popen("git status --porcelain")
  if not handle then return {} end
  local result = {}
  for line in handle:lines() do
    local file = line:match("^%s*%S+%s+(.+)")
    if file then
      table.insert(result, file)
    end
  end
  handle:close()
  return result
end

local function get_git_last_commit()
  local handle = io.popen("git diff-tree --no-commit-id --name-only -r HEAD")
  if not handle then return {} end
  local result = {}
  for line in handle:lines() do
    table.insert(result, line)
  end
  handle:close()
  return result
end

function M.render_ui()
  if not M.buf_id or not vim.api.nvim_buf_is_valid(M.buf_id) then
    return
  end

  local lines = { "=== Agent Observer ===", "" }

  table.insert(lines, "--- Active Session ---")
  if #M.active_session_files == 0 then
    table.insert(lines, "  (No files touched yet)")
  else
    for _, file in ipairs(M.active_session_files) do
      table.insert(lines, "  " .. file)
    end
  end
  table.insert(lines, "")

  table.insert(lines, "--- Pending Changes ---")
  local pending = get_git_status()
  if #pending == 0 then
    table.insert(lines, "  (No pending changes)")
  else
    for _, file in ipairs(pending) do
      table.insert(lines, "  " .. file)
    end
  end
  table.insert(lines, "")

  table.insert(lines, "--- Last Commit ---")
  local last_commit = get_git_last_commit()
  if #last_commit == 0 then
    table.insert(lines, "  (No files in last commit)")
  else
    for _, file in ipairs(last_commit) do
      table.insert(lines, "  " .. file)
    end
  end

  vim.api.nvim_buf_set_option(M.buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.buf_id, "modifiable", false)
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
    
    -- Filter out .git directory and the observer buffer itself
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
        M.render_ui()
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
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    vim.api.nvim_win_close(M.win_id, true)
    M.win_id = nil
    M.buf_id = nil
    return
  end

  -- Create scratch buffer
  M.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf_id, "filetype", "agent-observer")

  -- Create vertical split on the right
  vim.cmd("botright 40vsplit")
  M.win_id = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win_id, M.buf_id)

  M.render_ui()

  -- Keymaps in the observer buffer
  local opts = { buffer = M.buf_id, noremap = true, silent = true }
  
  -- Enter to open file
  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    local file = line:match("^%s+(.+)")
    if file then
      -- Move to the window on the left
      vim.cmd("wincmd h")
      -- Open the file
      vim.cmd("edit " .. file)
      -- Set as read-only but modifiable for streaming (Option B assumes support)
      vim.bo.readonly = true
      vim.bo.modifiable = false
    end
  end, opts)

  -- q to close
  vim.keymap.set("n", "q", function()
    M.toggle_diff()
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
