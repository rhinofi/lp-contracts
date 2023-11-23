let
  pkgs = import ./nix/pkgs.nix {};
  sources = import ./nix/sources.nix;
in
  pkgs.mkShell {
    inputsFrom = [
      # Inherit everything from dev-shell
      pkgs.dev-shell-with-node
    ];
    buildInputs = with pkgs; [
      direnv
      z3
      graphviz
    ];
  }
