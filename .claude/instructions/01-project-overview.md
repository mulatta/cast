# CAST Project Overview

## What is CAST?

**CAST** (Content-Addressed Storage Tool) is a Nix-integrated storage system for managing large-scale scientific databases with reproducibility and version control.

### Core Problem

- Large biological databases (NCBI, UniProt) lack proper version management
- Storing multi-gigabyte files in `/nix/store` is impractical
- Need deterministic builds and reproducibility for scientific workflows
- Want to separate data storage from metadata management

### Solution Architecture

A hybrid system that mimics `/nix/store` behavior for large data files:

```
┌─────────────────────────────────────┐
│ Nix Layer                           │
│  - Flake library (lib/*)            │
│  - Derivations (metadata only)      │
│  - Symlink farms                    │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│ Rust CLI (cast-cli)                 │
│  - BLAKE3 hashing                   │
│  - Transformation pipeline          │
│  - SQLite metadata tracking         │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│ Content-Addressed Storage (CAS)     │
│  $CAST_STORE/store/                 │
│    {hash[:2]}/{hash[2:4]}/{hash}    │
└─────────────────────────────────────┘
```

## Key Concepts

### 1. Content Addressing with BLAKE3

All data is stored by its cryptographic hash:
- Fast hashing (8+ GB/s on modern CPUs)
- Automatic deduplication
- Integrity verification

### 2. Pure Configuration Pattern

**No environment variables needed for builds**:

```nix
# Configure once
let castLib = cast.lib.configure {
  storePath = "/data/cast-store";
};

# Use everywhere - works with nix build --pure
in {
  db1 = castLib.mkDataset {...};
  db2 = castLib.transform {src = db1; ...};
}
```

### 3. Transformation Pipelines

Transform datasets while maintaining provenance:

```nix
castLib.transform {
  name = "ncbi-nr-mmseqs";
  src = ncbiRaw;
  builder = ''
    ${pkgs.mmseqs2}/bin/mmseqs createdb \
      "$SOURCE_DATA/nr.fasta" \
      "$CAST_OUTPUT/nr"
  '';
}
```

## Project Structure

```
cast/
├── flake.nix              # Main flake
├── lib/                   # Nix library functions
│   ├── mkDataset.nix     # Create dataset derivations
│   ├── transform.nix     # Transformation pipeline
│   ├── configure.nix     # Pure configuration
│   └── manifest.nix      # Manifest utilities
├── packages/
│   └── cast-cli/         # Rust CLI tool
├── examples/             # Usage examples
├── modules/              # NixOS modules
└── schemas/              # JSON schemas
```

## Implementation Phases

### ✅ Phase 1: MVP Core (Completed)
- Basic Nix library (`mkDataset`, `transform`)
- Rust CLI with BLAKE3 hashing
- Local storage backend
- Symlink farm generation

### ✅ Phase 2: Pure Configuration (Completed)
- `cast.lib.configure` function
- Works with `nix build --pure`
- cast-cli as Nix package
- Complete documentation

### 🚧 Phase 3: Database Management (In Progress)
- Common transformation builders (`toMMseqs`, `toBLAST`)
- NixOS module for system-wide database management
- `fetchDatabase` implementation

### 📋 Phase 4: Advanced Features (Future)
- Garbage collection
- Multi-tier storage (SSD/HDD)
- Remote storage backends
- Web UI for database browsing

## When to Load Detailed Docs

Load specific instruction files based on task:

| Task Type | Load File |
|-----------|-----------|
| Design questions | `02-architecture.md` |
| Setup/config | `03-configuration.md` |
| Implementation status | `04-implementation.md` |
| Task management | `05-taskmaster-quick.md` |

---

For detailed architecture and design decisions, see `02-architecture.md`.
