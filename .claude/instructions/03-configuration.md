# CAST Configuration Guide

## Quick Start: flake-parts Pattern

CAST uses flake-parts flakeModules for clean, type-safe configuration.

### Minimal Setup

```nix
{
  description = "My CAST project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      # Import CAST flakeModule
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        # Configure storage path
        cast.storePath = "/data/cast-store";

        # Use castLib (automatically injected)
        packages.my-dataset = castLib.mkDataset {
          name = "my-dataset";
          version = "1.0.0";
          manifest = ./manifest.json;
        };
      };
    };
}
```

**Build with pure evaluation**:
```bash
nix build .#my-dataset  # No --impure needed!
```

## Configuration Options

### `cast.storePath` (Required)

Root directory for content-addressed storage.

**Type**: `path` (absolute path string)

**Structure**:
```
$storePath/
├── store/           # Content-addressed files
│   └── {hash[:2]}/{hash[2:4]}/{full_hash}
├── meta.db          # SQLite metadata
└── config.toml      # Storage configuration
```

**Examples**:
```nix
# Development
cast.storePath = "/tmp/cast-dev";

# Production
cast.storePath = "/data/cast-store";

# Multi-user
cast.storePath = "/shared/lab-databases";
```

## Common Patterns

### Multi-Dataset Project

```nix
perSystem = { castLib, pkgs, ... }: {
  cast.storePath = "/data/databases";

  packages = {
    # Original datasets
    ncbi-nr-raw = castLib.mkDataset {
      name = "ncbi-nr-raw";
      version = "2024-01";
      manifest = ./manifests/ncbi-nr.json;
    };

    uniprot-raw = castLib.mkDataset {
      name = "uniprot-raw";
      version = "2024-01";
      manifest = ./manifests/uniprot.json;
    };

    # Transformations
    ncbi-nr-mmseqs = castLib.transform {
      name = "ncbi-nr-mmseqs";
      src = castLib.mkDataset {
        name = "ncbi-nr-raw";
        version = "2024-01";
        manifest = ./manifests/ncbi-nr.json;
      };
      builder = ''
        ${pkgs.mmseqs2}/bin/mmseqs createdb \
          "$SOURCE_DATA/nr.fasta" \
          "$CAST_OUTPUT/nr"
      '';
    };
  };
};
```

### Development Shell with Databases

```nix
perSystem = { castLib, pkgs, ... }: {
  cast.storePath = "/data/databases";

  devShells.default = pkgs.mkShell {
    packages = [
      pkgs.mmseqs2
      (castLib.mkDataset {
        name = "ncbi-nr";
        version = "2024-01";
        manifest = ./manifests/ncbi-nr.json;
      })
    ];

    shellHook = ''
      echo "NCBI NR available at: $CAST_DATASET_NCBI_NR"
    '';
  };
};
```

### Database Registry Flake

```nix
{
  description = "Lab database registry";

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        cast.storePath = "/shared/lab-databases";

        packages = {
          # Versioned databases
          ncbi-nr-2024-01 = castLib.mkDataset {...};
          ncbi-nr-2024-02 = castLib.mkDataset {...};
          uniprot-2024-01 = castLib.mkDataset {...};
        };
      };
    };
}
```

**Usage in other projects**:
```nix
{
  inputs.lab-databases.url = "git+file:///path/to/databases";

  perSystem = { ... }: {
    packages.myTool = pkgs.mkShell {
      buildInputs = [ inputs.lab-databases.packages.${system}.ncbi-nr-2024-01 ];
    };
  };
}
```

## Environment Variables (Auto-Generated)

When a dataset is used as build input, CAST automatically sets:

```bash
CAST_DATASET_<NAME>           # Path to /data directory
CAST_DATASET_<NAME>_VERSION   # Dataset version
CAST_DATASET_<NAME>_MANIFEST  # Path to manifest.json
```

**Name transformation**: `foo-bar` → `FOO_BAR`

**Note**: These are **outputs**, not configuration inputs.

## Storage Backend Configuration

### Future: `config.toml`

For future CLI-based operations:

```toml
[storage]
type = "local"
root = "/data/cast-store"

[download]
preferred_downloader = "aria2c"  # curl, wget, aria2c
max_concurrent = 4

[gc]
enabled = true
min_free_space = "100GB"
keep_recent_days = 30

# Future: multi-tier storage
# [[storage.tiers]]
# path = "/ssd/cast-hot"
# max_size = "500GB"
```

## Migration from Phase 1 (Legacy)

### Before (Environment Variables - Impure)

```bash
CAST_STORE=/data/cast nix build --impure .#my-dataset
```

### After (flakeModules - Pure)

```nix
perSystem = { castLib, ... }: {
  cast.storePath = "/data/cast";
  packages.my-dataset = castLib.mkDataset {...};
};
```

```bash
nix build .#my-dataset  # No --impure!
```

## Best Practices

### Development vs Production

```nix
perSystem = { config, ... }: {
  # Development: local temporary storage
  cast.storePath =
    if builtins.getEnv "CI" == "true"
    then "/tmp/cast-ci"
    else "/data/cast-dev";
};
```

### Per-System Storage Paths

```nix
perSystem = { system, ... }: {
  cast.storePath = {
    "x86_64-linux" = "/data/cast-store-x86";
    "aarch64-darwin" = "/Volumes/Data/cast-store";
  }.${system};
};
```

### Type Safety

The flakeModule validates configuration at evaluation time:

```nix
# ❌ Error: storePath must be absolute
cast.storePath = "relative/path";

# ✅ OK
cast.storePath = "/absolute/path";
```

## Troubleshooting

### "castLib not found"

Ensure you've imported the flakeModule:
```nix
imports = [ inputs.cast.flakeModules.default ];
```

### "storePath not set"

Add `cast.storePath` in your `perSystem`:
```nix
perSystem = { ... }: {
  cast.storePath = "/data/cast-store";
};
```

### Pure evaluation errors

Check that `storePath` is a literal string, not derived from environment:
```nix
# ❌ Breaks pure evaluation
cast.storePath = builtins.getEnv "CAST_STORE";

# ✅ Pure evaluation
cast.storePath = "/data/cast-store";
```

---

For detailed examples, see `examples/` directory.
For complete documentation, refer to `/CONFIGURATION.md`.
