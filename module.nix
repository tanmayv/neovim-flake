{ config, pkgs, lib, ... }:

with lib;

let
  neovimPackages = with pkgs; [
    # Core CLI tools used by plugins
    git
    gcc
    sqlite
    unzip
    cargo
    tree-sitter
    ripgrep
    fd
    fzf
    nodejs
    zsh
    tmux
    sc-im
    zk

    # Language servers / formatters from Nix instead of Mason
    lua-language-server
    clang-tools
    gopls
    zls
    rust-analyzer
    typescript-language-server
    basedpyright
    bash-language-server
    nixd
    sqls
    stylua
    shfmt
    python3Packages.debugpy
  ];
in
{
  options.neovim = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable Neovim configuration";
    };
  };

  config = mkIf config.neovim.enable {
    # 1. Enable Neovim in Home Manager
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      plugins = [
        {
          plugin = pkgs.vimPlugins.sqlite-lua;
        }
      ];
      extraPackages = neovimPackages;
    };

    # 2. Keep the same tools available in the user shell too
    home.packages = neovimPackages;

    # 3. Link AstroVim's configuration into ~/.config/nvim
    xdg.configFile = {
      "nvim/lua/plugins/nix-integration.lua".text = ''
        return {
          "nix-integration-dummy-name",
          dir = vim.fn.stdpath("config"),
          lazy = false,
          priority = 1000, -- High priority to ensure it loads first
          config = function()
            vim.g.sqlite_clib_path = "${pkgs.sqlite.out}/lib/libsqlite3${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}"
          end,
        }
      '';
      "nvim" = { source = ./dotfiles/nvim; recursive = true; };
      "prompts" = {
        source = ./dotfiles/prompts;
        recursive = true;
      };
    };
  };
}
