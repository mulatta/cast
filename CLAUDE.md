# CAST: Content-Addressed Storage Tool

## Project Overview

CAST is a Nix-integrated content-addressed storage system designed for managing large-scale scientific databases (NCBI, UniProt, etc.) with reproducibility and version control.

### Core Problem
- Large biological databases lack proper version management
- Storing multi-gigabyte files in `/nix/store` is impractical
- Need deterministic builds and reproducibility for scientific workflows
- Want to separate data storage from metadata management

### Solution
A hybrid system that mimics `/nix/store` behavior but for large data files:
- **Data layer**: Content-addressed storage (CAS) using BLAKE3 hashing
- **Metadata layer**: Nix derivations in `/nix/store` (only manifests and symlinks)
- **Integration**: Seamless Nix flake library for database management

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ User Projects                                           │
│  - Flake inputs (databases as dependencies)             │
│  - NixOS modules (system-wide database configuration)   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ CAST Library Flake (this project)                       │
│                                                          │
│  lib/                                                    │
│   ├── mkDataset.nix       - Create dataset derivations  │
│   ├── fetchDatabase.nix   - Download & register         │
│   ├── transform.nix       - Data transformation pipeline│
│   ├── symlinkSubset.nix   - Create subsets             │
│   └── manifest.nix        - Manifest utilities          │
│                                                          │
│  packages/                                               │
│   └── cast-cli/           - Rust CLI tool               │
└─────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────┬──────────────────────────────────┐
│ Metadata Layer       │ Rust CLI (cast-cli)              │
│ (/nix/store)         │                                  │
│                      │  Commands:                       │
│  - manifest.json     │   - put <file>    → CAS          │
│  - derivations       │   - get <hash>    → local path   │
│  - symlink farms     │   - fetch <url>   → download     │
│                      │   - transform     → pipeline     │
│  Example:            │   - gc            → cleanup      │
│  /nix/store/{hash}-  │                                  │
│    ncbi-nr/          │  Features:                       │
│    ├── manifest.json │   - BLAKE3 hashing               │
│    └── data/         │   - SQLite metadata              │
│        └── (symlinks)│   - Storage backend abstraction  │
└──────────────────────┴──────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ CAS Backend                                             │
│                                                          │
│  $CAST_STORE/                                           │
│   ├── store/                                            │
│   │   └── {hash[:2]}/{hash[2:4]}/{blake3_hash}         │
│   │       (actual data files)                           │
│   │                                                     │
│   ├── meta.db          - SQLite database               │
│   │   Tables:                                           │
│   │    - objects       (hash, size, refs, metadata)    │
│   │    - datasets      (name, version, manifest_hash)  │
│   │    - transformations (input→output mappings)       │
│   │                                                     │
│   └── config.toml      - Storage configuration         │
│       [storage]                                         │
│       root = "/data/cast-store"                         │
│       type = "local"  # extensible for future          │
└─────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Storage Format
- **Hierarchical hash structure**: `{hash[:2]}/{hash[2:4]}/{full_hash}`
- **Rationale**: Avoids single-directory performance issues, proven pattern (like git)
- **Extensible**: Storage backend trait allows future multi-tier storage (SSD/HDD)

### 2. Metadata Schema
- **Format**: JSON manifests + Nix derivations
- **Location**: Only manifests in `/nix/store`, actual data in CAS
- **Manifest contents**:
  - Dataset metadata (name, version, description)
  - Source information (URL, download date, server mtime)
  - Content inventory (files with BLAKE3 hashes)
  - Transformation provenance chain

### 3. Runtime Access Pattern
**Hybrid approach**:
- **Primary**: Symlink farms in `/nix/store` (Nix-native)
- **Secondary**: Environment variables for programmatic access
- **Example**:
  ```nix
  buildInputs = [ datasets.ncbi-nr ];
  # Results in: $CAST_DATASET_NCBI_NR pointing to symlink farm
  ```

### 4. Data Transformation Pipeline
- **Definition**: Nix derivations with special `CAST_OUTPUT` handling
- **Execution**: Builder runs → Rust CLI hashes outputs → stores in CAS
- **Caching**: Transformation results tracked in SQLite
- **Result**: Only manifest goes to `/nix/store`, data stays in CAS

### 5. Pure Configuration Pattern
**No environment variables required** for reproducible builds:
- **Primary**: `cast.lib.configure {storePath = "...";}` creates configured library
- **Override**: Individual `mkDataset` calls can override with explicit `storePath` parameter
- **Priority**: Explicit parameter > Configuration > Error (no implicit defaults)
- **Result**: Works with `nix build --pure` out of the box

Example:
```nix
let castLib = cast.lib.configure {storePath = "/data/cast";};
in castLib.mkDataset {...}  # Pure evaluation!
```

### 6. SQLite Usage
**Required** for:
- Fast hash lookups (avoid full directory scans)
- Metadata queries (e.g., "databases from 2024-01")
- Transformation cache
- Future garbage collection support
- Reference counting

## Project Structure

```
cast/
├── flake.nix              - Main flake definition
├── flake.lock
├── CLAUDE.md             - This file
├── README.md             - User documentation
│
├── lib/                   - Nix library functions
│   ├── default.nix
│   ├── mkDataset.nix     - Create dataset derivations
│   ├── fetchDatabase.nix - Download and register databases
│   ├── transform.nix     - Transformation pipeline
│   ├── symlinkSubset.nix - Create symlink subsets
│   ├── manifest.nix      - Manifest utilities
│   └── types.nix         - Type definitions
│
├── packages/
│   └── cast-cli/         - Rust CLI tool
│       ├── Cargo.toml
│       ├── Cargo.lock
│       ├── src/
│       │   ├── main.rs
│       │   ├── storage/
│       │   │   ├── mod.rs
│       │   │   ├── backend.rs    - Storage trait
│       │   │   └── local.rs      - Local storage impl
│       │   ├── hash.rs           - BLAKE3 hashing
│       │   ├── manifest.rs       - Manifest handling
│       │   └── db.rs             - SQLite operations
│       └── README.md
│
├── modules/              - NixOS modules (future)
│   └── cast.nix
│
├── examples/             - Example usage
│   ├── simple-dataset/
│   ├── transformation/
│   └── registry/
│
├── schemas/              - JSON schemas
│   ├── manifest-v1.json
│   └── config-v1.json
│
└── dev/                  - Development configuration
    ├── formatter.nix
    └── shell.nix
```

## Core Abstractions

### Manifest Schema (v1)

```json
{
  "schema_version": "1.0",
  "dataset": {
    "name": "ncbi-nr",
    "version": "2024-01-15",
    "description": "NCBI Non-Redundant Protein Database"
  },
  "source": {
    "url": "ftp://ftp.ncbi.nlm.nih.gov/blast/db/nr.tar.gz",
    "download_date": "2024-01-15T10:30:00Z",
    "server_mtime": "2024-01-14T18:00:00Z",
    "archive_hash": "blake3:af1234567890abcdef..."
  },
  "contents": [
    {
      "path": "nr.fasta",
      "hash": "blake3:b3cd567890abcdef...",
      "size": 123456789,
      "executable": false
    },
    {
      "path": "nr.index",
      "hash": "blake3:c4de678901bcdef...",
      "size": 987654,
      "executable": false
    }
  ],
  "transformations": [
    {
      "type": "extract",
      "from": "blake3:af1234567890abcdef...",
      "params": { "format": "tar.gz" }
    }
  ]
}
```

### Rust Storage Backend Trait

```rust
pub trait StorageBackend {
    /// Store data and return its BLAKE3 hash
    fn put(&self, data: impl Read) -> Result<Blake3Hash>;

    /// Retrieve path to data by hash (may be symlink to CAS)
    fn get(&self, hash: &Blake3Hash) -> Result<PathBuf>;

    /// Check if hash exists in storage
    fn exists(&self, hash: &Blake3Hash) -> bool;

    /// Delete data by hash (respects reference counting)
    fn delete(&self, hash: &Blake3Hash) -> Result<()>;

    /// Register metadata for a dataset
    fn register_dataset(&self, manifest: &Manifest) -> Result<()>;
}

// Current implementation: LocalStorage
// Future: TieredStorage, RemoteStorage, etc.
```

### Nix Library API

```nix
cast.lib = {
  # ═══════════════════════════════════════════════════════
  # Configuration Function (Phase 2)
  # ═══════════════════════════════════════════════════════

  # Create a configured CAST library instance
  configure = {
    storePath,      # Required: absolute path to CAST store
    # Future options:
    # preferredDownloader ? "aria2c",
    # compressionLevel ? 9,
  }: {
    # Returns configured library with bound functions
    mkDataset = {...};
    transform = {...};
    fetchDatabase = {...};  # Future
    symlinkSubset = {...};
    inherit manifest types;
  };

  # ═══════════════════════════════════════════════════════
  # Direct Functions (for backward compatibility)
  # ═══════════════════════════════════════════════════════

  # Create a dataset derivation from manifest
  mkDataset = config: {
    name,           # Dataset name
    version,        # Version string
    manifest,       # Path to manifest.json or attrset
    storePath ? null, # Optional: override configured storePath
  }: derivation;

  # Download and register a database (Future)
  fetchDatabase = config: {
    name,
    url,
    hash ? null,    # Optional: expected BLAKE3 hash
    extract ? false, # Auto-extract archives
    metadata ? {},  # Additional metadata
  }: manifest;

  # Transform dataset
  transform = config: {
    name,
    src,            # Source dataset
    builder,        # Transformation function/script
    outputs ? ["out"], # Output structure
    params ? {},    # Transformation parameters (as JSON)
  }: derivation;

  # Create symlink subset
  symlinkSubset = {
    name,
    paths,          # List of { name, path } or datasets
  }: derivation;

  # ═══════════════════════════════════════════════════════
  # Utilities
  # ═══════════════════════════════════════════════════════

  manifest = {
    readManifest = path: attrset;
    hashToPath = storePath: hash: path;
    manifestToEnv = manifest: { VAR = "value"; ... };
    # ... other manifest utilities
  };

  types = {
    validators = {
      isValidBlake3Hash = hash: bool;
      isValidManifest = manifest: bool;
      # ... other validators
    };
  };
};
```

**Recommended Usage Pattern**:
```nix
# 1. Configure once
let castLib = cast.lib.configure {storePath = "/data/cast";};

# 2. Use configured library
in {
  db1 = castLib.mkDataset {...};
  db2 = castLib.mkDataset {...};
  db3 = castLib.transform {src = db1; ...};
}
```

## Usage Examples

### Example 1: Basic Database Registration (Pure)

```nix
{
  inputs.cast.url = "github:yourusername/cast";

  outputs = { cast, ... }: let
    # Configure CAST library
    castLib = cast.lib.configure {
      storePath = "/data/lab-databases";
    };
  in {
    packages.x86_64-linux.ncbi-nr = castLib.mkDataset {
      name = "ncbi-nr";
      version = "2024-01-15";
      manifest = ./manifests/ncbi-nr-2024-01-15.json;
    };
  };
}
```

**Pure evaluation**: No `--impure` flag needed!
```bash
nix build .#ncbi-nr  # Works with --pure
```

### Example 2: Transform Pipeline

```nix
{ cast, pkgs }:
let
  # Configure library
  castLib = cast.lib.configure {
    storePath = "/data/databases";
  };

  # Original FASTA dataset
  ncbiRaw = castLib.mkDataset {
    name = "ncbi-nr-raw";
    version = "2024-01-15";
    manifest = ./ncbi-nr.json;
  };

  # Transform to MMseqs2 format
  ncbiMmseqs = castLib.transform {
    name = "ncbi-nr-mmseqs";
    src = ncbiRaw;

    builder = ''
      ${pkgs.mmseqs2}/bin/mmseqs createdb \
        "$SOURCE_DATA/nr.fasta" \
        "$CAST_OUTPUT/nr"

      ${pkgs.mmseqs2}/bin/mmseqs createindex \
        "$CAST_OUTPUT/nr" \
        "$CAST_OUTPUT/tmp"
    '';
  };
in
pkgs.mkShell {
  buildInputs = [ pkgs.mmseqs2 ncbiMmseqs ];

  shellHook = ''
    echo "MMseqs database: $CAST_DATASET_NCBI_NR_MMSEQS"
  '';
}
```

### Example 3: Multi-Version Database Registry

```nix
# databases/flake.nix
{
  inputs.cast.url = "github:yourusername/cast";

  outputs = { cast, ... }: let
    # Single configuration for all databases
    castLib = cast.lib.configure {
      storePath = "/data/shared-databases";
    };
  in {
    # Export as flake outputs
    databases = {
      ncbi-nr = {
        "2024-01-15" = cast.lib.mkDataset { ... };
        "2024-02-01" = cast.lib.mkDataset { ... };
      };
      uniprot = {
        "2024-01" = cast.lib.mkDataset { ... };
      };
    };
  };
}

# Usage in another project
{
  inputs.databases.url = "git+file:///path/to/databases";

  outputs = { databases, ... }: {
    packages.x86_64-linux.myTool = pkgs.mkShell {
      buildInputs = [ databases.databases.ncbi-nr."2024-01-15" ];
    };
  };
}
```

## Implementation Phases

### Phase 1: MVP Core ✅ (Completed)
- [x] Project structure skeleton
- [x] Manifest schema definition
- [x] Nix library abstractions (`cast.lib.*`)
- [x] Rust CLI basic structure
- [x] BLAKE3 hashing implementation
- [x] Local storage backend
- [x] SQLite schema and basic operations
- [x] `cast.lib.mkDataset` implementation
- [x] `cast.lib.transform` implementation
- [x] Symlink farm generation
- [x] Environment variable injection
- [x] Manifest validation
- [x] Transformation provenance tracking

### Phase 2: Pure Configuration ✅ (Completed)
- [x] `cast.lib.configure` function
- [x] Pure configuration pattern (no environment variables)
- [x] Works with `nix build --pure`
- [x] Type-checked configuration
- [x] cast-cli as Nix package
- [x] gitignore.nix integration
- [x] Complete database registry examples
- [x] flake-parts integration pattern
- [x] Comprehensive documentation (README, CONFIGURATION.md)

**Success Criteria Met**:
- ✅ Zero environment variables required
- ✅ All config type-checked
- ✅ Works with `nix build --pure`
- ✅ cast-cli package available
- ✅ Complete database registry example

### Phase 3: Database Management (In Progress)
- [ ] Common transformation builders (`lib/builders.nix`)
  - [ ] `toMMseqs` - Convert FASTA to MMseqs2 format
  - [ ] `toBLAST` - Convert FASTA to BLAST format
  - [ ] `toDiamond` - Convert FASTA to Diamond format
- [ ] NixOS module for system-wide database management
- [ ] `fetchDatabase` implementation
- [ ] Automatic manifest generation
- [ ] Archive extraction

### Phase 4: Advanced Features (Future)
- [ ] Garbage collection (`cast gc`)
- [ ] Multi-tier storage (SSD/HDD)
- [ ] Remote storage backends
- [ ] Remote registry synchronization
- [ ] Web UI for database browsing
- [ ] Performance optimizations
  - [ ] Parallel hashing for multi-file datasets
  - [ ] Incremental updates (rsync-style)
  - [ ] Compression (zstd) for cold storage

## Development Guidelines

### Nix Code Style
- Use `cast.lib.` namespace for all library functions
- Prefer attribute sets over positional arguments
- Include docstrings for all public functions
- Follow nixpkgs conventions

### Rust Code Style
- Use `cargo fmt` and `cargo clippy`
- Error handling with `anyhow` for CLI, `thiserror` for libraries
- Async I/O for network operations (tokio)
- Comprehensive logging with `tracing`

### Testing Strategy
- Unit tests for Rust code
- Integration tests with temporary CAST stores
- Nix evaluation tests in `flake.nix` checks
- Example projects as end-to-end tests

## Configuration

See [`CONFIGURATION.md`](CONFIGURATION.md) for comprehensive configuration guide.

### Pure Configuration Pattern (Phase 2)

**No environment variables needed for builds**:

```nix
# 1. Configure library with explicit settings
let castLib = cast.lib.configure {
  storePath = "/data/cast-store";
};

# 2. Use configured library
in castLib.mkDataset {...}
```

**Configuration Priority**:
1. Explicit `storePath` parameter in `mkDataset` call
2. Configuration passed to `cast.lib.configure`
3. Error with helpful message (no implicit defaults)

**Result**: Works with `nix build --pure` ✅

### Environment Variables (Auto-Generated Outputs)

When a dataset is used as a build input, CAST automatically sets:

- `CAST_DATASET_<NAME>`: Path to dataset `/data` directory
- `CAST_DATASET_<NAME>_VERSION`: Dataset version
- `CAST_DATASET_<NAME>_MANIFEST`: Path to manifest.json

These are **outputs**, not configuration inputs. Name transformation: `foo-bar` → `FOO_BAR`

### Future Configuration (`config.toml`)

For future CLI-based operations (not yet implemented):

```toml
[storage]
type = "local"
root = "/data/cast-store"

[download]
preferred_downloader = "aria2c"  # curl, wget, aria2c
max_concurrent = 4
retry_attempts = 3

[compression]
algorithm = "zstd"  # zstd, gzip, none
level = 9  # 0-9

[gc]
enabled = true
min_free_space = "100GB"
keep_recent_days = 30

# Future: multi-tier storage
# [[storage.tiers]]
# path = "/ssd/cast-hot"
# max_size = "500GB"
# [[storage.tiers]]
# path = "/hdd/cast-cold"
```

## Technical Decisions Log

### Why BLAKE3?
- Extremely fast on large files (8 GB/s+)
- Cryptographically secure (unlike xxHash)
- Parallelizable (uses SIMD)
- Suitable for content addressing

### Why SQLite?
- Embedded (no server needed)
- Fast hash lookups
- ACID guarantees
- Simple backup (single file)
- Proven at scale

### Why Rust for CLI?
- Memory safety for storage operations
- Excellent performance for hashing
- Strong ecosystem (blake3, sqlx, tokio)
- Easy Nix integration via rustPlatform

### Why Pure Configuration (No Environment Variables)?
**Phase 2 Design Decision**

**Problems with environment variables**:
- Requires `nix build --impure` (breaks reproducibility)
- Hard to track which env vars are needed
- Different values on different machines → different results
- Violates Nix's pure evaluation model

**Benefits of pure configuration**:
- ✅ Works with `nix build --pure` (fully reproducible)
- ✅ All configuration visible in flake.nix
- ✅ Type-checked at evaluation time
- ✅ Same input → same output guaranteed
- ✅ Better error messages (configuration missing vs wrong env var)
- ✅ Easier to test (no environment setup needed)

**Implementation**:
```nix
# Before (Phase 1 - impure)
CAST_STORE=/data/cast nix build --impure

# After (Phase 2 - pure)
let castLib = cast.lib.configure {storePath = "/data/cast";};
in nix build  # No flags needed!
```

**Trade-off**: Requires explicit configuration in flake.nix, but this is actually a benefit for reproducibility.

### Why Not Store Everything in /nix/store?
- Multi-gigabyte files cause:
  - Slow garbage collection
  - Excessive disk usage (no deduplication across machines)
  - Poor performance (single directory with millions of files)
- CAS allows targeted storage management

## Related Projects

- **Nix/NixOS**: Foundation for reproducibility
- **IPFS**: Content-addressed storage (but too heavyweight)
- **Git LFS**: Large file storage (but requires Git)
- **Bazel**: Build system with content addressing (but not Nix-integrated)
- **Tvix store**: Nix store reimplementation (complementary approach)

## Future Considerations

### Multi-Storage Backend
- Hot/Cold tiered storage (SSD/HDD)
- Remote storage (S3, HTTP)
- Peer-to-peer sharing between lab machines

### Performance Optimizations
- Parallel hashing for multi-file datasets
- Incremental updates (rsync-style)
- Compression (zstd) for cold storage

### Collaboration Features
- Shared CAS store on network filesystem
- Registry mirroring
- Dataset provenance tracking
- Citation metadata (DOI, publication info)

---

**Status**: Phase 2 Complete (Pure Configuration & Documentation)
**Last Updated**: 2025-11-18

### Recent Milestones
- ✅ **2025-11-18**: Phase 2 completed - Pure configuration pattern implemented
  - cast.lib.configure function
  - Works with `nix build --pure`
  - cast-cli as Nix package
  - Complete documentation (README.md, CONFIGURATION.md)
  - Database registry examples with flake-parts
- ✅ **2025-11-17**: Phase 1 completed - MVP core functionality
  - mkDataset and transform functions
  - BLAKE3 hashing and local storage
  - Transformation provenance tracking

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main CLAUDE.md file.**
@./.taskmaster/CLAUDE.md
