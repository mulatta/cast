# Database Registry Example

This example demonstrates creating a database registry flake that exports multiple versioned datasets.

## Overview

Shows how to:
- Create a centralized database registry
- Export multiple datasets as flake outputs
- Version databases properly
- Use registry databases in other projects

## Structure

A database registry flake that provides:
- Multiple database types (NCBI, UniProt, etc.)
- Multiple versions of each database
- Consistent naming and organization
- Easy integration as a flake input

## Files (to be implemented in task 10)

- `flake.nix`: Registry flake with multiple database outputs
- `manifests/`: Directory of manifest files
  - `ncbi-nr-2024-01-15.json`
  - `ncbi-nr-2024-02-01.json`
  - `uniprot-2024-01.json`
  - etc.

## Usage

### As a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    databases.url = "git+file:///path/to/registry";
  };

  outputs = { nixpkgs, databases, ... }: {
    packages.x86_64-linux.myTool = pkgs.mkShell {
      buildInputs = [
        databases.databases.ncbi-nr."2024-01-15"
        databases.databases.uniprot."2024-01"
      ];
    };
  };
}
```

### Browsing available databases:

```bash
nix flake show
```

## Implementation Status

⏳ **Pending** - Will be implemented in task 10 (Example and Documentation)
