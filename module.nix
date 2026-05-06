{ config, pkgs, lib, ... }:

with lib;

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
    };

    # 2. Install Neovim and AstroVim dependencies
    home.packages = with pkgs; [
      gcc
      sqlite
      unzip
      cargo
      ripgrep  # For Telescope
      fd       # For Telescope
      nodejs   # Required by some LSPs / Mason
    ];

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
