# CAST Architecture & Design Decisions

## Core Abstractions

### Manifest Schema (v1)

JSON format for dataset metadata:

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
    }
  ],
  "transformations": [
    {
      "type": "extract",
      "from": "blake3:af1234567890abcdef...",
      "params": {"format": "tar.gz"}
    }
  ]
}
```

### Rust Storage Backend Trait

```rust
pub trait StorageBackend {
    /// Store data and return its BLAKE3 hash
    fn put(&self, data: impl Read) -> Result<Blake3Hash>;

    /// Retrieve path to data by hash
    fn get(&self, hash: &Blake3Hash) -> Result<PathBuf>;

    /// Check if hash exists in storage
    fn exists(&self, hash: &Blake3Hash) -> bool;

    /// Delete data by hash (respects reference counting)
    fn delete(&self, hash: &Blake3Hash) -> Result<()>;

    /// Register metadata for a dataset
    fn register_dataset(&self, manifest: &Manifest) -> Result<()>;
}
```

**Current Implementation**: `LocalStorage`
**Future**: `TieredStorage`, `RemoteStorage`

### Nix Library API

```nix
cast.lib = {
  # Configuration
  configure = {storePath, ...}: configuredLib;

  # Core functions (use configured library)
  mkDataset = config: {name, version, manifest, ...}: derivation;
  transform = config: {name, src, builder, ...}: derivation;
  fetchDatabase = config: {name, url, ...}: manifest;  # Future
  symlinkSubset = {name, paths, ...}: derivation;

  # Utilities
  manifest = {...};  # Manifest utilities
  types = {...};     # Type validators
};
```

**Usage Pattern**:
```nix
let castLib = cast.lib.configure {storePath = "/data/cast";};
in castLib.mkDataset {...}  # Pure evaluation!
```

## Design Decisions

### 1. Why BLAKE3?

- ✅ Extremely fast (8+ GB/s on large files)
- ✅ Cryptographically secure (unlike xxHash)
- ✅ Parallelizable (uses SIMD)
- ✅ Suitable for content addressing

### 2. Why SQLite?

- ✅ Embedded (no server needed)
- ✅ Fast hash lookups
- ✅ ACID guarantees
- ✅ Simple backup (single file)
- ✅ Proven at scale

**Required for**:
- Fast hash lookups (avoid full directory scans)
- Metadata queries
- Transformation cache
- Future garbage collection
- Reference counting

### 3. Why Hierarchical Hash Structure?

`$CAST_STORE/store/{hash[:2]}/{hash[2:4]}/{full_hash}`

- ✅ Avoids single-directory performance issues
- ✅ Proven pattern (Git, Docker Registry)
- ✅ Scalable to millions of objects
- ✅ Easy to implement tiered storage

### 4. Why Pure Configuration (No Environment Variables)?

**Phase 2 Design Decision**

**Problems with environment variables**:
- ❌ Requires `nix build --impure`
- ❌ Different values → different results
- ❌ Hard to track dependencies
- ❌ Violates Nix's pure evaluation

**Benefits of pure configuration**:
- ✅ Works with `nix build --pure`
- ✅ All configuration visible in `flake.nix`
- ✅ Type-checked at evaluation time
- ✅ Same input → same output guaranteed
- ✅ Easier to test

**Implementation**:
```nix
# Before (Phase 1 - impure)
CAST_STORE=/data/cast nix build --impure

# After (Phase 2 - pure)
let castLib = cast.lib.configure {storePath = "/data/cast";};
in nix build  # No --impure needed!
```

### 5. Why Rust for CLI?

- ✅ Memory safety for storage operations
- ✅ Excellent performance for hashing
- ✅ Strong ecosystem (blake3, sqlx, tokio)
- ✅ Easy Nix integration via rustPlatform

### 6. Why Not Store Everything in `/nix/store`?

Multi-gigabyte files cause:
- ❌ Slow garbage collection
- ❌ Excessive disk usage
- ❌ Poor performance (millions of files in single directory)

CAS allows:
- ✅ Targeted storage management
- ✅ Deduplication across projects
- ✅ Hierarchical organization

## Runtime Access Pattern

### Hybrid Approach

**Primary**: Symlink farms in `/nix/store`
```nix
buildInputs = [datasets.ncbi-nr];
# Results in symlink farm at $out/data/
```

**Secondary**: Auto-generated environment variables
```bash
CAST_DATASET_NCBI_NR="/nix/store/.../data"
CAST_DATASET_NCBI_NR_VERSION="2024-01-15"
CAST_DATASET_NCBI_NR_MANIFEST="/nix/store/.../manifest.json"
```

**Note**: Environment variables are **outputs**, not configuration inputs.

## Data Transformation Pipeline

### Definition
Nix derivations with special `CAST_OUTPUT` handling:

```nix
castLib.transform {
  name = "ncbi-nr-mmseqs";
  src = ncbiRaw;
  builder = ''
    # Source data available at $SOURCE_DATA
    ${pkgs.mmseqs2}/bin/mmseqs createdb \
      "$SOURCE_DATA/nr.fasta" \
      "$CAST_OUTPUT/nr"

    # Outputs written to $CAST_OUTPUT are automatically hashed
  '';
}
```

### Execution Flow

1. Builder runs in Nix sandbox
2. Outputs written to `$CAST_OUTPUT`
3. Rust CLI hashes all outputs
4. Data stored in CAS
5. Manifest with hashes goes to `/nix/store`
6. Transformation tracked in SQLite

### Caching

- Transformation results cached by input hash + builder hash
- Avoid re-running expensive transformations
- Invalidates on source or builder changes

## Storage Backend Architecture

### Current: Local Storage

```
$CAST_STORE/
├── store/                    # Actual data files
│   └── {hash[:2]}/{hash[2:4]}/{blake3_hash}
├── meta.db                   # SQLite metadata
│   Tables:
│    - objects       (hash, size, refs, metadata)
│    - datasets      (name, version, manifest_hash)
│    - transformations (input→output mappings)
└── config.toml              # Storage configuration
```

### Future: Multi-Tier Storage

**Design for extensibility**:

```rust
pub enum StorageBackend {
    Local(LocalStorage),
    Tiered(TieredStorage),  // SSD + HDD
    Remote(RemoteStorage),  // HTTP, S3
}
```

**Use cases**:
- Hot tier (SSD): Recent/frequently accessed
- Cold tier (HDD): Archive storage
- Remote: Shared lab storage, mirrors

## Related Projects

- **Nix/NixOS**: Foundation for reproducibility
- **IPFS**: Content-addressed storage (too heavyweight)
- **Git LFS**: Large file storage (requires Git)
- **Bazel**: Build system with content addressing (not Nix-integrated)
- **Tvix store**: Nix store reimplementation (complementary)

## Technical Guidelines

### Nix Code Style
- Use `cast.lib.` namespace for all library functions
- Prefer attribute sets over positional arguments
- Include docstrings for all public functions
- Follow nixpkgs conventions

### Rust Code Style
- Use `cargo fmt` and `cargo clippy`
- Error handling: `anyhow` for CLI, `thiserror` for libraries
- Async I/O for network operations (tokio)
- Comprehensive logging with `tracing`

### Testing Strategy
- Unit tests for Rust code
- Integration tests with temporary CAST stores
- Nix evaluation tests in `flake.nix` checks
- Example projects as end-to-end tests

---

For configuration details, see `03-configuration.md`.
For implementation status, see `04-implementation.md`.
