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

### 5. Storage Configuration Priority
1. `$CAST_STORE` environment variable
2. Flake's `defaultStorePath` attribute
3. `~/.config/cast/config.toml`
4. Default: `~/.cache/cast`

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
  # Create a dataset derivation from manifest
  mkDataset = {
    name,           # Dataset name
    version,        # Version string
    manifest,       # Path to manifest.json or attrset
    storePath ? null, # Optional: override CAST_STORE
  }: derivation;

  # Download and register a database
  fetchDatabase = {
    name,
    url,
    hash ? null,    # Optional: expected BLAKE3 hash
    extract ? false, # Auto-extract archives
    metadata ? {},  # Additional metadata
  }: manifest;

  # Transform dataset
  transform = {
    name,
    src,            # Source dataset
    builder,        # Transformation function/script
    outputs ? ["out"], # Output structure
  }: derivation;

  # Create symlink subset
  symlinkSubset = {
    name,
    paths,          # List of { name, path } or datasets
  }: derivation;

  # Utilities
  readManifest = path: attrset;
  hashToPath = hash: path;
  manifestToEnv = manifest: { VAR = "value"; ... };
};
```

## Usage Examples

### Example 1: Basic Database Registration

```nix
{
  inputs.cast.url = "github:yourusername/cast";

  outputs = { cast, ... }: {
    packages.x86_64-linux.ncbi-nr = cast.lib.mkDataset {
      name = "ncbi-nr";
      version = "2024-01-15";
      manifest = ./manifests/ncbi-nr-2024-01-15.json;
    };
  };
}
```

### Example 2: Download and Transform

```nix
{ cast, pkgs }:
let
  # Download original archive
  ncbiNrArchive = cast.lib.fetchDatabase {
    name = "ncbi-nr-archive";
    url = "ftp://ftp.ncbi.nlm.nih.gov/blast/db/nr.tar.gz";
    extract = true;
  };

  # Transform to mmseqs database
  ncbiNrMmseqs = cast.lib.transform {
    name = "ncbi-nr-mmseqs";
    src = ncbiNrArchive;

    builder = pkgs.writeShellScript "build-mmseqs" ''
      mmseqs createdb ${ncbiNrArchive}/nr.fasta $CAST_OUTPUT/nr
      mmseqs createindex $CAST_OUTPUT/nr $CAST_OUTPUT/tmp
    '';
  };
in
pkgs.mkShell {
  buildInputs = [ pkgs.mmseqs2 ncbiNrMmseqs ];
}
```

### Example 3: Database Registry

```nix
# databases/flake.nix
{
  inputs.cast.url = "github:yourusername/cast";

  outputs = { cast, ... }: {
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

### Phase 1: MVP Core (Current Focus)
- [ ] Project structure skeleton
- [ ] Manifest schema definition
- [ ] Nix library abstractions (`cast.lib.*`)
- [ ] Rust CLI basic structure
- [ ] BLAKE3 hashing implementation
- [ ] Local storage backend
- [ ] SQLite schema and basic operations

### Phase 2: Data Management
- [ ] `cast fetch` command
- [ ] `cast put` / `cast get` commands
- [ ] Automatic symlink farm generation
- [ ] Environment variable injection
- [ ] Manifest validation

### Phase 3: Transformation Pipeline
- [ ] `cast.lib.transform` implementation
- [ ] Transformation caching
- [ ] Dependency graph tracking
- [ ] Common transformations library (extract, mmseqs, blast)

### Phase 4: Advanced Features
- [ ] Garbage collection (`cast gc`)
- [ ] Multi-storage backend support
- [ ] NixOS module
- [ ] Remote registry synchronization
- [ ] Web UI for database browsing

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

### Storage Configuration (`config.toml`)

```toml
[storage]
type = "local"
root = "/data/cast-store"

[storage.gc]
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

### Environment Variables

- `CAST_STORE`: Override storage root path
- `CAST_CONFIG`: Override config file location
- `CAST_LOG`: Log level (error/warn/info/debug/trace)
- `CAST_DATASET_<NAME>`: Auto-set by mkDataset (uppercase, - → _)

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
- Easy Nix integration via naersk/crane

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

**Status**: Phase 1 (Design & Skeleton Implementation)
**Last Updated**: 2025-11-17

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main CLAUDE.md file.**
@./.taskmaster/CLAUDE.md
