# CAST Configuration Guide

This document provides comprehensive guidance on configuring CAST for various use cases.

## Table of Contents

- [Overview](#overview)
- [Pure Configuration Pattern](#pure-configuration-pattern)
- [Configuration API](#configuration-api)
- [Configuration Priority](#configuration-priority)
- [Common Patterns](#common-patterns)
- [Environment Variables](#environment-variables)
- [Advanced Scenarios](#advanced-scenarios)
- [Troubleshooting](#troubleshooting)

## Overview

CAST uses a **pure configuration pattern** that eliminates the need for environment variables, making builds reproducible and deterministic. All configuration is specified explicitly in Nix code.

### Design Principles

1. **Explicit over implicit**: No hidden defaults or environment variable dependencies
2. **Type-safe**: Configuration is validated at Nix evaluation time
3. **Reproducible**: Same configuration always produces same result
4. **Works with `--pure`**: No impure environment dependencies

## Pure Configuration Pattern

The core of CAST configuration is the `configure` function, which creates a configured library instance.

### Basic Pattern

```nix
{
  inputs.cast.url = "github:yourusername/cast";

  outputs = { self, nixpkgs, cast }: let
    # Create configured CAST library
    castLib = cast.lib.configure {
      storePath = "/data/cast-store";
    };
  in {
    packages.x86_64-linux = {
      my-dataset = castLib.mkDataset {...};
    };
  };
}
```

### Why This Pattern?

**Before (Phase 1 - Impure)**:
```nix
# ❌ Requires environment variable
packages.my-dataset = cast.lib.mkDataset {...};

# Terminal:
CAST_STORE=/data/cast nix build --impure .#my-dataset
```

**After (Phase 2 - Pure)**:
```nix
# ✅ Pure evaluation
let castLib = cast.lib.configure {storePath = "/data/cast";};
in packages.my-dataset = castLib.mkDataset {...};

# Terminal:
nix build .#my-dataset  # No --impure needed!
```

## Configuration API

### `cast.lib.configure`

Creates a configured CAST library instance with all functions bound to the configuration.

```nix
castLib = cast.lib.configure {
  storePath = string;
  # Future options:
  # preferredDownloader = "aria2c" | "curl" | "wget";
  # compressionLevel = 0..9;
  # cacheTTL = int; # seconds
}
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `storePath` | string | Yes | Absolute path to CAST storage directory |

#### Returns

Configured library object with methods:
- `mkDataset` - Create dataset derivations
- `transform` - Transform datasets
- `fetchDatabase` - Download databases (future)
- `symlinkSubset` - Create dataset subsets

#### Example

```nix
let
  castLib = cast.lib.configure {
    storePath = "/data/lab-databases";
  };
in {
  # All functions use the configured storePath
  ncbi-nr = castLib.mkDataset {...};
  uniprot = castLib.mkDataset {...};
  ncbi-mmseqs = castLib.transform {...};
}
```

### `castLib.mkDataset`

Create a dataset using the configured library.

```nix
castLib.mkDataset {
  name = string;
  version = string;
  manifest = path | attrset;
  storePath = string | null;  # Optional override
}
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Dataset name (alphanumeric + `-_`) |
| `version` | string | Yes | Version identifier |
| `manifest` | path/attrset | Yes | Manifest file or inline definition |
| `storePath` | string | No | Override configured storePath for this dataset |

## Configuration Priority

When resolving `storePath`, CAST follows this priority order:

```
1. Explicit parameter in mkDataset
   ↓ (if null)
2. Configuration from cast.lib.configure
   ↓ (if not provided)
3. Error with helpful message
```

### Priority Examples

**Highest priority: Explicit parameter**
```nix
let castLib = cast.lib.configure {storePath = "/data/cast";};
in castLib.mkDataset {
  name = "special-db";
  storePath = "/mnt/ssd/fast-storage";  # ← Uses this
  # ...
}
```

**Normal priority: Configuration**
```nix
let castLib = cast.lib.configure {storePath = "/data/cast";};
in castLib.mkDataset {
  name = "normal-db";  # ← Uses /data/cast from configure
  # ...
}
```

**Error case: No configuration**
```nix
# ❌ This will error
cast.lib.mkDataset {
  name = "my-db";
  # Error: storePath not configured
}
```

Error message:
```
error: CAST storePath not configured.

Please configure storePath using one of these methods:

Method 1: Use cast.lib.configure (recommended)
  let castLib = cast.lib.configure {storePath = "/data/cast";};
  in castLib.mkDataset {...}

Method 2: Pass explicit parameter
  cast.lib.mkDataset {
    storePath = "/data/cast";
    name = "...";
    manifest = ...;
  }
```

## Common Patterns

### 1. Single Project Configuration

For simple projects with one storage location:

```nix
{
  outputs = { self, nixpkgs, cast }: let
    castLib = cast.lib.configure {
      storePath = "/data/project-databases";
    };
  in {
    packages.x86_64-linux = {
      db1 = castLib.mkDataset {...};
      db2 = castLib.mkDataset {...};
      db3 = castLib.mkDataset {...};
    };
  };
}
```

### 2. Development vs Production

Use different storage paths for different environments:

```nix
{
  outputs = { self, nixpkgs, cast }: let
    # Development: local cache
    devCastLib = cast.lib.configure {
      storePath = builtins.getEnv "HOME" + "/.cache/cast-dev";
    };

    # Production: shared storage
    prodCastLib = cast.lib.configure {
      storePath = "/data/lab-databases";
    };
  in {
    packages.x86_64-linux = {
      # Development packages
      dev-ncbi = devCastLib.mkDataset {...};

      # Production packages
      prod-ncbi = prodCastLib.mkDataset {...};
    };
  };
}
```

### 3. flake-parts Integration

Recommended pattern for complex projects:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];

      perSystem = {config, pkgs, system, ...}: let
        # Define configuration once
        castConfig = {
          storePath = "/data/shared-databases";
        };

        # Create configured library
        castLib = inputs.cast.lib.configure castConfig;
      in {
        packages = {
          # Use castLib throughout
          ncbi-nr = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-01-15";
            manifest = ./manifests/ncbi-nr.json;
          };

          # Transformations can reference packages
          ncbi-nr-mmseqs = castLib.transform {
            name = "ncbi-nr-mmseqs";
            src = config.packages.ncbi-nr;
            builder = ''
              mmseqs createdb "$SOURCE_DATA/nr.fasta" "$CAST_OUTPUT/nr"
            '';
          };
        };

        # Dev shell with databases
        devShells.default = pkgs.mkShell {
          buildInputs = [
            config.packages.ncbi-nr
            config.packages.ncbi-nr-mmseqs
          ];
          shellHook = ''
            echo "Databases loaded from: ${castConfig.storePath}"
          '';
        };
      };
    };
}
```

### 4. Multi-Tier Storage

Use different storage paths for different performance needs:

```nix
let
  # Fast storage for frequently used databases
  fastCast = cast.lib.configure {
    storePath = "/mnt/nvme/cast-hot";
  };

  # Bulk storage for archives
  bulkCast = cast.lib.configure {
    storePath = "/mnt/hdd/cast-cold";
  };
in {
  packages = {
    # Hot: Latest databases on NVMe
    ncbi-nr-latest = fastCast.mkDataset {...};
    uniprot-latest = fastCast.mkDataset {...};

    # Cold: Historical versions on HDD
    ncbi-nr-2023-archive = bulkCast.mkDataset {...};
    uniprot-2023-archive = bulkCast.mkDataset {...};
  };
}
```

### 5. Per-Project Isolation

Isolate databases for different projects:

```nix
let
  project1Cast = cast.lib.configure {
    storePath = "/data/project1/databases";
  };

  project2Cast = cast.lib.configure {
    storePath = "/data/project2/databases";
  };
in {
  packages = {
    # Project 1 databases
    p1-ncbi = project1Cast.mkDataset {...};

    # Project 2 databases (same content, different storage)
    p2-ncbi = project2Cast.mkDataset {...};
  };
}
```

### 6. Shared Configuration Module

Extract configuration to a reusable module:

```nix
# db-config.nix
{cast}: {
  production = cast.lib.configure {
    storePath = "/data/production/databases";
  };

  staging = cast.lib.configure {
    storePath = "/data/staging/databases";
  };

  development = cast.lib.configure {
    storePath = "/tmp/dev-databases";
  };
}
```

```nix
# flake.nix
{
  outputs = {cast, ...}: let
    dbConfig = import ./db-config.nix {inherit cast;};
  in {
    packages.x86_64-linux = {
      prod-db = dbConfig.production.mkDataset {...};
      dev-db = dbConfig.development.mkDataset {...};
    };
  };
}
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

Name transformation: `foo-bar_baz` → `FOO_BAR_BAZ` (uppercase, hyphens and underscores preserved)

### Example

```nix
let
  castLib = cast.lib.configure {storePath = "/data/cast";};

  ncbiNr = castLib.mkDataset {
    name = "ncbi-nr";
    version = "2024-01-15";
    manifest = ./ncbi-nr.json;
  };
in
pkgs.mkShell {
  buildInputs = [ncbiNr];

  shellHook = ''
    echo "NCBI NR path: $CAST_DATASET_NCBI_NR"
    echo "Version: $CAST_DATASET_NCBI_NR_VERSION"
    echo "Manifest: $CAST_DATASET_NCBI_NR_MANIFEST"

    # Use in scripts
    mmseqs search \
      query.fasta \
      "$CAST_DATASET_NCBI_NR/nr.fasta" \
      results.tsv
  '';
}
```

### Multiple Datasets

```nix
pkgs.mkDerivation {
  name = "analysis";
  buildInputs = [
    datasets.ncbi-nr
    datasets.uniprot
    datasets.pfam
  ];

  buildPhase = ''
    # All datasets available via env vars
    combine-databases \
      "$CAST_DATASET_NCBI_NR" \
      "$CAST_DATASET_UNIPROT" \
      "$CAST_DATASET_PFAM"
  '';
}
```

## Advanced Scenarios

### Dynamic Storage Path

Use Nix expressions for dynamic paths:

```nix
let
  # Read from file
  storePath = builtins.readFile ./storage-path.txt;

  # Or use environment during evaluation
  storePath = builtins.getEnv "LAB_DATABASE_ROOT" + "/cast";

  castLib = cast.lib.configure {inherit storePath;};
in {
  packages.db = castLib.mkDataset {...};
}
```

**Note**: Using `builtins.getEnv` makes evaluation impure. Prefer explicit configuration.

### Conditional Configuration

```nix
let
  isCI = builtins.getEnv "CI" == "true";

  castLib = cast.lib.configure {
    storePath =
      if isCI
      then "/tmp/ci-databases"
      else "/data/production/databases";
  };
in {
  packages.db = castLib.mkDataset {...};
}
```

### Override for Specific Dataset

```nix
let
  # Default configuration
  castLib = cast.lib.configure {
    storePath = "/data/standard-storage";
  };
in {
  packages = {
    # Uses default storage
    normal-db = castLib.mkDataset {
      name = "normal";
      version = "1.0";
      manifest = ./normal.json;
    };

    # Override for special case
    fast-db = castLib.mkDataset {
      name = "fast";
      version = "1.0";
      manifest = ./fast.json;
      storePath = "/mnt/nvme/fast-storage";  # Override
    };
  };
}
```

### NixOS System Integration (Future)

When the NixOS module is available:

```nix
# /etc/nixos/configuration.nix
{
  services.cast = {
    enable = true;
    storePath = "/var/lib/cast";
    databases = {
      ncbi-nr = {...};
      uniprot = {...};
    };
  };
}
```

Users can then reference system-wide databases:

```nix
{
  outputs = {cast, ...}: {
    packages.analysis = pkgs.mkDerivation {
      buildInputs = [
        cast.systemDatabases.ncbi-nr
      ];
    };
  };
}
```

## Troubleshooting

### Error: storePath not configured

**Problem**:
```
error: CAST storePath not configured.
```

**Solution**:
```nix
# Always use cast.lib.configure
let castLib = cast.lib.configure {storePath = "/data/cast";};
in castLib.mkDataset {...}
```

### Error: storePath must be absolute path

**Problem**:
```
error: storePath must be an absolute path, got: "./databases"
```

**Solution**:
```nix
# Use absolute path
cast.lib.configure {storePath = "/data/databases";}

# Or use self.outPath for flake-relative paths
cast.lib.configure {storePath = self.outPath + "/databases";}
```

### Warning: Using builtins.getEnv

**Problem**:
```
warning: Git tree is dirty
# Build fails with --pure
```

**Solution**:
```nix
# Bad: Impure evaluation
storePath = builtins.getEnv "CAST_STORE"

# Good: Explicit configuration
storePath = "/data/cast-store"
```

### Environment Variable Not Set

**Problem**:
```bash
$ echo $CAST_DATASET_NCBI_NR

# Empty
```

**Solution**: Ensure dataset is in `buildInputs`:

```nix
pkgs.mkShell {
  buildInputs = [ncbiNr];  # ← Required for env vars
}
```

### Storage Path Doesn't Exist

**Problem**:
```
error: cannot create directory '/data/cast-store': Permission denied
```

**Solution**:
```bash
# Create directory with correct permissions
sudo mkdir -p /data/cast-store
sudo chown $USER:$USER /data/cast-store
chmod 755 /data/cast-store
```

### Confusion: configure vs mkDataset

**Problem**: Not sure when to use which function.

**Solution**:

```nix
# 1. Configure ONCE per project/storage location
let castLib = cast.lib.configure {storePath = "..."};

# 2. Use configured library many times
in {
  db1 = castLib.mkDataset {...};
  db2 = castLib.mkDataset {...};
  db3 = castLib.mkDataset {...};
}
```

Think of `configure` as "create a factory", and `mkDataset` as "use the factory".

## Best Practices

1. **Configure once, use many times**
   ```nix
   let castLib = cast.lib.configure {...};
   in {
     db1 = castLib.mkDataset {...};
     db2 = castLib.mkDataset {...};
   }
   ```

2. **Use explicit paths**
   ```nix
   # Good
   storePath = "/data/lab-databases"

   # Avoid
   storePath = builtins.getEnv "STORAGE_PATH"
   ```

3. **Separate configuration from datasets**
   ```nix
   # db-config.nix
   {storePath}: cast.lib.configure {inherit storePath;}

   # flake.nix
   let castLib = import ./db-config.nix {storePath = "/data/cast";};
   ```

4. **Document storage locations**
   ```nix
   # Store databases in dedicated partition
   # /data/databases (5TB NVMe SSD)
   storePath = "/data/databases";
   ```

5. **Use flake-parts for complex projects**
   - Cleaner configuration management
   - Better modularization
   - Easier testing

## Future Configuration Options

These options are planned for future releases:

```nix
cast.lib.configure {
  storePath = "/data/cast";

  # Download configuration
  preferredDownloader = "aria2c";  # curl, wget, aria2c
  maxConcurrentDownloads = 4;
  retryAttempts = 3;

  # Compression
  compressionLevel = 9;  # 0-9
  compressionAlgorithm = "zstd";  # zstd, gzip, none

  # Cache
  cacheTTL = 86400;  # seconds
  cacheStrategy = "lru";  # lru, lfu, fifo

  # Garbage collection
  gc = {
    enabled = true;
    minFreeSpace = "100GB";
    keepRecentDays = 30;
  };
}
```

## Reference Links

- [README.md](README.md) - General overview and examples
- [CLAUDE.md](CLAUDE.md) - Architecture and design decisions
- [examples/](examples/) - Working examples
  - [simple-dataset/](examples/simple-dataset/) - Basic usage
  - [transformation/](examples/transformation/) - Transformations
  - [registry/](examples/registry/) - Multi-version management
  - [database-registry/](examples/database-registry/) - Production pattern with flake-parts

---

For questions or issues, please see:
- [Issues](https://github.com/yourusername/cast/issues)
- [Discussions](https://github.com/yourusername/cast/discussions)
