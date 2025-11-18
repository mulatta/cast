# CAST library functions
# This module exports all CAST-specific Nix library functions
{
  lib,
  pkgs,
  ...
}: rec {
  # Create a dataset derivation from manifest
  # Accepts config parameter for storePath configuration
  mkDataset = config: import ./mkDataset.nix {inherit lib pkgs config;};

  # Download and register a database
  # Note: fetchDatabase doesn't need config yet, but we keep it for future extension
  fetchDatabase = config:
    import ./fetchDatabase.nix {inherit lib pkgs;}
    // {
      mkDataset = mkDataset config;
    };

  # Transform dataset
  # Note: transform doesn't currently need config, but we keep the config parameter
  # in the API for consistency with other functions
  transform = _config: import ./transform.nix {inherit lib pkgs;};

  # Create symlink subset (no config needed)
  symlinkSubset = import ./symlinkSubset.nix {inherit lib pkgs;};

  # Manifest utilities (no config needed)
  manifest = import ./manifest.nix {inherit lib;};

  # Type definitions (no config needed)
  types = import ./types.nix {inherit lib;};

  # Common transformation builders for bioinformatics
  # These are convenience wrappers that use castLib.transform internally
  builders = import ./builders.nix {inherit lib pkgs;};

  # Convenience wrapper: configure once, use everywhere
  # Usage: let castLib = cast.lib.configure config.cast; in castLib.mkDataset { ... }
  configure = config: let
    # Create configured library instance
    configuredLib = {
      inherit config;
      mkDataset = mkDataset config;
      fetchDatabase = fetchDatabase config;
      transform = transform config;
      inherit symlinkSubset manifest types;
    };
  in
    # Add builders that use the configured library
    configuredLib
    // {
      # Bioinformatics database format converters
      toMMseqs = builders.toMMseqs configuredLib;
      toBLAST = builders.toBLAST configuredLib;
      toDiamond = builders.toDiamond configuredLib;

      # Utilities
      extractArchive = builders.extractArchive configuredLib;
    };
}
