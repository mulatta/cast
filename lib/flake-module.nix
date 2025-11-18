# CAST flake-parts module
# This module provides automatic castLib injection into perSystem
{
  self,
  lib,
  config,
  flake-parts-lib,
  ...
}: let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options = {
    # Per-system CAST configuration
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      system,
      ...
    }: {
      options.cast = mkOption {
        type = types.submodule {
          options = {
            storePath = mkOption {
              type = types.path;
              description = ''
                Path to the CAST content-addressed storage directory.
                This is where actual data files will be stored using BLAKE3 hashes.

                This can be configured per-system to use different storage locations
                for different architectures (e.g., SSD for x86_64-linux, HDD for others).
              '';
              example = "/data/cast-store";
            };
          };
        };
        default = {};
        description = ''
          CAST (Content-Addressed Storage Tool) configuration.

          CAST separates data storage (in CAS) from metadata (in /nix/store),
          enabling efficient management of large scientific databases.
        '';
      };
    });
  };

  config = {
    # Inject castLib into perSystem when storePath is configured
    perSystem = {
      config,
      system,
      ...
    }: let
      # Check if storePath is configured
      hasStorePath = config.cast ? storePath;

      # Import CAST lib functions directly to avoid circular dependency
      # (self.lib may not be available when this module is evaluated)
      castLibFunctions = import ./. {
        inherit lib;
        # Create minimal pkgs for the lib functions
        # This is only used for the configure function, not for actual builds
        pkgs = import self.inputs.nixpkgs {
          system = "x86_64-linux"; # Dummy system, actual builds use correct system
          overlays = [];
        };
      };
    in
      lib.mkIf hasStorePath {
        # Inject configured castLib into perSystem module args
        _module.args.castLib = castLibFunctions.configure {
          storePath = config.cast.storePath;
        };
      };
  };
}
