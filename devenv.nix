{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  # https://devenv.sh/packages/
  packages = with pkgs; [
    stylua
    alejandra
  ];

  # https://devenv.sh/languages/
  languages.lua.enable = true;
  languages.nix.enable = true;
}
