# Agent Observer

The `agent-observer` is a Neovim plugin designed to monitor file changes made by background agents in real-time. It provides a sidebar UI to visualize active session files, pending changes, and the last commit, with support for automatic diff viewing.

## Features

- **Real-time Monitoring**: Uses filesystem watchers to detect file changes immediately.
- **VCS Integration**: Supports both Git and Mercurial (with specific optimizations for Google's `google3` workspace).
- **Auto Mode**: Automatically opens the diff of the last changed file in the main pane.
- **Lazy Loading**: Loaded on demand via keymap or command to save resources.
- **Hybrid Dynamic Watching (Mercurial)**: To avoid overwhelming file watchers at the root of large repositories, it dynamically watches only the parent directories of changed files, and files directly if they are in the root.
- **Fast Diffs (Mercurial)**: Attempts to read base content directly from `/google/src/files/head/depot/` for speed.
- **CWD Filtering**: Option to focus only on changes within the current working directory.

## Usage

### Commands
- `:AgentObserverToggle`: Open or close the Agent Observer tab.

### Keybindings
- `<leader>ao`: Toggle Agent Observer.

In the Observer sidebar:
- `o`: Open file in main pane (keeps focus on sidebar).
- `<CR>`: Open file in main pane and move focus.
- `s`: Open file in horizontal split.
- `v`: Open file in vertical split.
- `d`: Open diff against HEAD.
- `l`: Expand/Collapse tree node.
- `h`: Toggle hidden files.
- `a`: Toggle Auto Mode.
- `r`: Manual refresh and reset countdown.
- `q`: Close Observer tab.

## Configuration

Default configuration in `init.lua`:

```lua
M.config = {
  vcs_adapter = "git", -- default
  expand_level = 2, -- default expand level
  show_hidden = false, -- default show hidden files
  poll_interval = 60, -- default polling interval in seconds
}
```

## Color Coding

- **Green** (`DiagnosticOk`): Changed but not yet opened.
- **Red** (`DiagnosticError`): Deleted (cannot be opened, but supports diff).
- **Headings**: Different colors for each section to improve readability.

## Debugging

A **"Watched Paths (Debug)"** section is available at the bottom of the sidebar to show which paths are currently being watched by the dynamic watchers. Notifications will appear when events are received.
