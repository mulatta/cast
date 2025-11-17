# CAST library functions
# This module exports all CAST-specific Nix library functions
{
  lib,
  pkgs,
  ...
}: rec {
  # Create a dataset derivation from manifest
  mkDataset = import ./mkDataset.nix {inherit lib pkgs;};

  # Download and register a database
  fetchDatabase = import ./fetchDatabase.nix {inherit lib pkgs mkDataset;};

  # Transform dataset
  transform = import ./transform.nix {inherit lib pkgs;};

  # Create symlink subset
  symlinkSubset = import ./symlinkSubset.nix {inherit lib pkgs;};

  # Manifest utilities
  manifest = import ./manifest.nix {inherit lib;};

  # Type definitions
  types = import ./types.nix {inherit lib;};
}
