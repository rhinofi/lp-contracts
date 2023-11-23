{
  sources ? import ./sources.nix,
  config ? {},
  system ? builtins.currentSystem,
  overlays ? []
}:
let
  # This can be used to work against local version of copy of launch-deversifi
  # repo instead of specific git commit defined in sources.json
  # pkgsBasePath = ../../launch-deversifi;
  pkgsBasePath = sources.launch-deversifi;
  pkgsPath = pkgsBasePath + "/nix/pkgs-with-default-ci.nix";

  allOverlays =
    overlays
  ;
in
  import pkgsPath { inherit config system; overlays = allOverlays; }
