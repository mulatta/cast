# CAST Configuration Guide

Complete guide to configuring CAST using the flake-parts flakeModules pattern.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration Options](#configuration-options)
- [Advanced Patterns](#advanced-patterns)
- [Migration Guide](#migration-guide)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

CAST uses the flake-parts framework to provide a clean, type-safe configuration system through flakeModules. This approach:

- **Eliminates environment variables**: All configuration is explicit in your flake.nix
- **Provides automatic injection**: `castLib` is automatically available in perSystem
- **Works with pure evaluation**: Compatible with `nix build --pure`
- **Type-checked**: Configuration errors are caught at evaluation time
- **Modular**: Easy to compose with other flake-parts modules

### Key Concepts

- **flakeModule**: A reusable flake-parts module that defines options and provides functionality
- **perSystem**: A flake-parts mechanism for per-system configuration
- **cast.storePath**: The primary configuration option for CAST storage location
- **castLib**: Automatically injected library providing `mkDataset`, `transform`, etc.

## Quick Start

### Minimal Configuration

The simplest CAST setup:

```nix
{
  description = "My CAST project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      # Import CAST flakeModule
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        # Configure CAST storage path
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

### Build and Verify

```bash
# Build works with pure evaluation
nix build .#my-dataset

# No --impure flag needed!
```

## Configuration Options

### `cast.storePath`

The root directory for content-addressed storage.

**Type**: `path` (string representing an absolute path)

**Required**: Yes (when using CAST functions)

**Description**: Specifies where CAST stores actual file contents using BLAKE3 content-addressing. The directory structure will be:
```
$storePath/
├── store/           # Content-addressed files
│   └── {hash[:2]}/{hash[2:4]}/{full_hash}
├── meta.db          # SQLite metadata (future)
└── config.toml      # Storage configuration (future)
```

**Examples**:

```nix
# Simple path
cast.storePath = "/data/cast-store";

# Home directory relative
cast.storePath = builtins.getEnv "HOME" + "/.cache/cast";

# System-specific
cast.storePath =
  if system == "x86_64-linux"
  then "/fast/nvme/cast"
  else "/bulk/hdd/cast";
```

**Common Values**:
- Production: `/data/cast-store`, `/var/lib/cast`
- Development: `$HOME/.cache/cast`, `/tmp/cast-dev`
- CI/Testing: `/tmp/cast-ci`

### Future Options (Planned)

The following options are planned for future releases:

```nix
perSystem = { ... }: {
  cast = {
    storePath = "/data/cast";

    # Future: Download configuration
    # preferredDownloader = "aria2c";  # curl, wget, aria2c
    # maxConcurrent = 4;
    # retryAttempts = 3;

    # Future: Compression settings
    # compression = {
    #   algorithm = "zstd";  # zstd, gzip, none
    #   level = 9;
    # };

    # Future: Garbage collection
    # gc = {
    #   enabled = true;
    #   minFreeSpace = "100GB";
    #   keepRecentDays = 30;
    # };
  };
};
```

## Advanced Patterns

### Per-System Configuration

Different storage paths for different architectures:

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" ];
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { system, castLib, ... }: {
        cast.storePath =
          if system == "x86_64-linux" then "/fast/nvme/cast"
          else if system == "aarch64-linux" then "/bulk/hdd/cast"
          else if system == "x86_64-darwin" then "/Volumes/Data/cast"
          else throw "Unsupported system: ${system}";

        packages.my-db = castLib.mkDataset {
          name = "my-db";
          version = "1.0.0";
          manifest = ./manifest.json;
        };
      };
    };
}
```

### Environment-Based Configuration

Different configurations for different environments:

```nix
{
  perSystem = { castLib, ... }: let
    # Detect environment
    isProduction = builtins.getEnv "CAST_PRODUCTION" == "1";
    isCI = builtins.getEnv "CI" == "true";
  in {
    cast.storePath =
      if isProduction then "/production/cast"
      else if isCI then "/tmp/cast-ci"
      else builtins.getEnv "HOME" + "/.cache/cast";

    packages.my-db = castLib.mkDataset {
      name = "my-db";
      version = "1.0.0";
      manifest = ./manifest.json;
    };
  };
}
```

**Usage**:
```bash
# Production build
CAST_PRODUCTION=1 nix build .#my-db

# CI build
CI=true nix build .#my-db

# Development build (default)
nix build .#my-db
```

### Multi-Tier Storage

Use different storage paths for different datasets (hot/cold storage):

```nix
{
  perSystem = { castLib, ... }: {
    # Default to cold storage
    cast.storePath = "/bulk/hdd/cast-cold";

    packages = {
      # Frequently accessed - override to hot storage
      ncbi-nr-latest = castLib.mkDataset {
        name = "ncbi-nr";
        version = "2024-03-01";
        manifest = ./ncbi-nr-latest.json;
        storePath = "/fast/nvme/cast-hot";  # Explicit override
      };

      # Archive data - use default cold storage
      ncbi-nr-2023 = castLib.mkDataset {
        name = "ncbi-nr";
        version = "2023-12-01";
        manifest = ./ncbi-nr-2023.json;
        # No storePath = uses cast.storePath
      };
    };
  };
}
```

### Shared Registry Pattern

Create a shared database registry that other projects can import:

**Registry flake** (`databases/flake.nix`):
```nix
{
  description = "Lab Shared Database Registry";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        cast.storePath = "/data/shared-databases";

        packages = let
          # Define all database versions
          ncbi-versions = {
            "ncbi-nr-2024-01" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-01-15";
              manifest = ./manifests/ncbi-nr-2024-01.json;
            };
            "ncbi-nr-2024-02" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-02-01";
              manifest = ./manifests/ncbi-nr-2024-02.json;
            };
          };
        in
          ncbi-versions // {
            # Convenience aliases
            ncbi-nr-latest = ncbi-versions."ncbi-nr-2024-02";
          };
      };
    };
}
```

**Consumer project**:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    lab-databases.url = "git+ssh://lab-server/databases";
  };

  outputs = { self, nixpkgs, lab-databases }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system}.analysis = pkgs.stdenv.mkDerivation {
      name = "my-analysis";
      buildInputs = [
        lab-databases.packages.${system}.ncbi-nr-latest
        pkgs.blast
      ];

      buildPhase = ''
        blastp -query query.fasta -db $CAST_DATASET_NCBI_NR/nr
      '';
    };
  };
}
```

### Conditional Dataset Loading

Load different datasets based on configuration:

```nix
{
  perSystem = { castLib, ... }: let
    # Configuration flags
    useFullDataset = builtins.getEnv "FULL_DATASET" == "1";
  in {
    cast.storePath = "/data/cast";

    packages = {
      my-dataset =
        if useFullDataset
        then castLib.mkDataset {
          name = "ncbi-nr-full";
          version = "2024-01";
          manifest = ./ncbi-nr-full.json;
        }
        else castLib.mkDataset {
          name = "ncbi-nr-mini";
          version = "2024-01";
          manifest = ./ncbi-nr-mini.json;
        };
    };
  };
}
```

## Migration Guide

### From v0.2 (configure pattern) to v0.3 (flakeModules pattern)

If you're upgrading from the older `cast.lib.configure` pattern, follow this guide.

#### Before (v0.2)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    cast.url = "github:yourusername/cast";
  };

  outputs = { self, nixpkgs, cast }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # Manual configuration
    castLib = cast.lib.configure {
      storePath = "/data/cast-store";
    };
  in {
    packages.${system} = {
      my-db = castLib.mkDataset {
        name = "my-db";
        version = "1.0.0";
        manifest = ./manifest.json;
      };
    };
  };
}
```

#### After (v0.3)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      # Import CAST flakeModule
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        # Declarative configuration
        cast.storePath = "/data/cast-store";

        # castLib automatically injected
        packages.my-db = castLib.mkDataset {
          name = "my-db";
          version = "1.0.0";
          manifest = ./manifest.json;
        };
      };
    };
}
```

#### Migration Checklist

- [ ] Add `flake-parts` and `systems` to inputs
- [ ] Replace `outputs = { self, nixpkgs, cast }: ...` with `outputs = inputs @ { flake-parts, ... }:`
- [ ] Wrap with `flake-parts.lib.mkFlake { inherit inputs; } { ... }`
- [ ] Add `systems = import inputs.systems;`
- [ ] Add `imports = [ inputs.cast.flakeModules.default ];`
- [ ] Move configuration into `perSystem = { castLib, ... }: { ... }`
- [ ] Replace `cast.lib.configure { ... }` with `cast.storePath = ...`
- [ ] Remove `let castLib = ...` binding (now auto-injected)
- [ ] Update package references from `self.packages.${system}.foo` to `config.packages.foo`
- [ ] Test with `nix flake check` and `nix build`

#### Common Gotchas

**1. Forgetting to import flakeModule**

```nix
# ❌ Wrong: Missing imports
perSystem = { castLib, ... }: {
  cast.storePath = "/data/cast";
}

# ✅ Correct: Import flakeModule first
imports = [ inputs.cast.flakeModules.default ];
perSystem = { castLib, ... }: {
  cast.storePath = "/data/cast";
}
```

**2. Using old package references**

```nix
# ❌ Wrong: Old self.packages.${system} pattern
devShells.default = pkgs.mkShell {
  buildInputs = [ self.packages.${system}.my-db ];
};

# ✅ Correct: Use config.packages
perSystem = { config, pkgs, ... }: {
  devShells.default = pkgs.mkShell {
    buildInputs = [ config.packages.my-db ];
  };
}
```

**3. Trying to use configure alongside flakeModule**

```nix
# ❌ Wrong: Mixing old and new patterns
perSystem = { ... }: let
  castLib = inputs.cast.lib.configure {...};  # Don't do this!
in {
  cast.storePath = "/data/cast";
}

# ✅ Correct: Use only flakeModule pattern
perSystem = { castLib, ... }: {
  cast.storePath = "/data/cast";
  # castLib is automatically injected
}
```

## Troubleshooting

### "storePath not configured"

**Error**:
```
error: CAST storePath not configured.

Please use CAST's flakeModule to configure storePath:
...
```

**Cause**: Missing `cast.storePath` configuration or missing flakeModule import.

**Solution**:
```nix
{
  # 1. Import CAST flakeModule
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, ... }: {
    # 2. Configure storePath
    cast.storePath = "/data/cast-store";

    # 3. Now you can use castLib
    packages.my-db = castLib.mkDataset {...};
  };
}
```

### "castLib is not defined"

**Error**:
```
error: attribute 'castLib' missing
```

**Cause**: Missing CAST flakeModule import in `imports`.

**Solution**:
```nix
{
  # Add this line
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, ... }: {  # Now castLib is available
    ...
  };
}
```

### "The option `cast.storePath' does not exist"

**Error**:
```
error: The option `perSystem.<system>.cast.storePath' does not exist.
```

**Cause**: CAST flakeModule not imported.

**Solution**:
```nix
{
  # Add CAST flakeModule to imports
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { ... }: {
    cast.storePath = "/data/cast";  # Now this option exists
  };
}
```

### "Permission denied" when building

**Error**:
```
error: cannot create directory '/data/cast-store': Permission denied
```

**Cause**: The configured `storePath` directory doesn't exist or lacks permissions.

**Solution**:
```bash
# Create the directory
sudo mkdir -p /data/cast-store

# Set ownership
sudo chown $USER:$USER /data/cast-store

# Set permissions
chmod 755 /data/cast-store
```

### Storage path in wrong location

**Issue**: CAST is using `/tmp` instead of your configured path.

**Debug**:
```bash
# Check what storePath is being used
nix eval .#packages.x86_64-linux.my-dataset.castStorePath

# Should output: "/data/cast-store"
```

**Common Causes**:
1. Using explicit `storePath` parameter in `mkDataset` that overrides config
2. Environment variable influencing path (check `builtins.getEnv` usage)
3. System-specific configuration not matching your system

## Best Practices

### 1. Use Explicit Paths

```nix
# ✅ Good: Explicit, reproducible
cast.storePath = "/data/cast-store";

# ⚠️ Caution: Uses environment variable (less reproducible)
cast.storePath = builtins.getEnv "HOME" + "/.cache/cast";

# ❌ Avoid: Relies on current directory
cast.storePath = ./cast-store;  # Problematic in /nix/store context
```

### 2. Validate Storage Paths

Add sanity checks for critical paths:

```nix
perSystem = { castLib, ... }: let
  storePath = "/data/cast-store";

  # Validate path is absolute
  isAbsolute = builtins.match "/.*" storePath != null;
in {
  cast.storePath =
    if isAbsolute
    then storePath
    else throw "CAST storePath must be absolute: ${storePath}";

  packages = {...};
}
```

### 3. Document Your Configuration

Add comments explaining configuration choices:

```nix
perSystem = { castLib, system, ... }: {
  # CAST Storage Configuration
  # Production: NVMe SSD for hot data (x86_64-linux)
  # Archive: HDD for cold storage (aarch64-linux)
  cast.storePath =
    if system == "x86_64-linux"
    then "/fast/nvme/cast"      # 2TB NVMe SSD
    else "/archive/hdd/cast";   # 20TB HDD array

  packages = {...};
}
```

### 4. Use Constants for Paths

For complex projects, define paths as constants:

```nix
perSystem = { castLib, ... }: let
  # Storage configuration constants
  paths = {
    production = "/data/prod/cast";
    staging = "/data/staging/cast";
    development = "/tmp/cast-dev";
  };

  environment = builtins.getEnv "DEPLOY_ENV";

  storePath =
    if environment == "production" then paths.production
    else if environment == "staging" then paths.staging
    else paths.development;
in {
  cast.storePath = storePath;

  packages = {...};
}
```

### 5. Separate Configuration Modules

For large projects, extract CAST configuration into a separate module:

**`nix/cast-config.nix`**:
```nix
{ inputs, ... }: {
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { system, ... }: {
    cast.storePath =
      if system == "x86_64-linux" then "/data/cast"
      else if system == "aarch64-linux" then "/data/cast-arm"
      else throw "Unsupported system: ${system}";
  };
}
```

**`flake.nix`**:
```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        ./nix/cast-config.nix  # CAST configuration
        # ... other modules
      ];

      perSystem = { castLib, ... }: {
        packages = {
          my-db = castLib.mkDataset {...};
        };
      };
    };
}
```

### 6. Test Configuration Changes

Always test after configuration changes:

```bash
# 1. Check flake structure
nix flake check

# 2. Verify configuration is applied
nix eval .#packages.x86_64-linux.my-dataset.castStorePath

# 3. Test build
nix build .#my-dataset

# 4. Verify environment variables in shell
nix develop -c bash -c 'echo $CAST_DATASET_MY_DATASET'
```

## Environment Variables

CAST automatically sets environment variables for each dataset. These are **outputs**, not configuration inputs.

### Auto-Generated Variables

When you use a dataset as a build input, CAST sets:

```bash
CAST_DATASET_<NAME>          # Path to /data directory
CAST_DATASET_<NAME>_VERSION  # Dataset version
CAST_DATASET_<NAME>_MANIFEST # Path to manifest.json
```

Name transformation: `foo-bar` → `FOO_BAR` (uppercase, hyphens to underscores)

### Example Usage

```nix
{
  perSystem = { castLib, pkgs, config, ... }: {
    cast.storePath = "/data/cast";

    packages.ncbi-nr = castLib.mkDataset {
      name = "ncbi-nr";
      version = "2024-01-15";
      manifest = ./ncbi-nr.json;
    };

    devShells.default = pkgs.mkShell {
      buildInputs = [ config.packages.ncbi-nr ];

      shellHook = ''
        echo "NCBI NR path: $CAST_DATASET_NCBI_NR"
        echo "Version: $CAST_DATASET_NCBI_NR_VERSION"

        # Use in scripts
        blastp \
          -query query.fasta \
          -db "$CAST_DATASET_NCBI_NR/nr.fasta" \
          -out results.txt
      '';
    };
  };
}
```

## See Also

- [README.md](README.md) - Project overview and quick start
- [README_KR.md](README_KR.md) - Korean language README
- [USAGE_KR.md](USAGE_KR.md) - Detailed usage guide (Korean)
- [CLAUDE.md](CLAUDE.md) - Architecture and design decisions
- [flake-parts documentation](https://flake.parts/) - flake-parts framework guide

---

**Questions or issues?**
- GitHub Issues: https://github.com/yourusername/cast/issues
- GitHub Discussions: https://github.com/yourusername/cast/discussions
