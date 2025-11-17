# CAST: Content-Addressed Storage Tool - Product Requirements Document

## Project Overview

CAST is a Nix-integrated content-addressed storage system designed for managing large-scale scientific databases (NCBI, UniProt, etc.) with reproducibility and version control.

### Core Problem
- Large biological databases lack proper version management
- Storing multi-gigabyte files in `/nix/store` is impractical
- Need deterministic builds and reproducibility for scientific workflows
- Want to separate data storage from metadata management

### Solution Architecture
A hybrid system that mimics `/nix/store` behavior but for large data files:
- **Data layer**: Content-addressed storage (CAS) using BLAKE3 hashing
- **Metadata layer**: Nix derivations in `/nix/store` (only manifests and symlinks)
- **Integration**: Seamless Nix flake library for database management

## Phase 1: MVP Core (Current Focus)

### 1.1 Project Structure Skeleton
Create the complete directory structure for the CAST project including:
- Main flake.nix definition
- lib/ directory with Nix library functions (mkDataset, fetchDatabase, transform, symlinkSubset, manifest, types)
- packages/cast-cli/ directory for Rust CLI tool
- modules/ for NixOS modules
- examples/ with sample usage
- schemas/ for JSON schemas
- dev/ for development configuration

### 1.2 Manifest Schema Definition
Define and document the JSON manifest schema v1 including:
- Schema version field
- Dataset metadata (name, version, description)
- Source information (URL, download date, server mtime, archive hash)
- Contents array with file paths, BLAKE3 hashes, sizes, executable flags
- Transformations array for provenance tracking
- Create JSON schema file in schemas/manifest-v1.json

### 1.3 Nix Library Abstractions
Implement the core Nix library API (cast.lib.*) with:
- mkDataset: Create dataset derivations from manifest
- fetchDatabase: Download and register databases
- transform: Data transformation pipeline
- symlinkSubset: Create symlink subsets
- Utility functions: readManifest, hashToPath, manifestToEnv
- Type definitions in types.nix
- Proper documentation and docstrings

### 1.4 Rust CLI Basic Structure
Set up the Rust CLI tool foundation:
- Cargo.toml with dependencies (blake3, sqlx, tokio, clap, anyhow, thiserror, tracing)
- src/main.rs with CLI argument parsing
- Module structure for storage/, hash, manifest, db
- Command structure (put, get, fetch, transform, gc)
- Error types and logging setup
- Basic README for cast-cli

### 1.5 BLAKE3 Hashing Implementation
Implement BLAKE3 content hashing in Rust:
- hash.rs module with BLAKE3 hashing functions
- Support for streaming large files efficiently
- Hash formatting and validation
- Integration with storage backend
- Unit tests for hashing correctness

### 1.6 Local Storage Backend
Implement the local storage backend with:
- Storage trait definition (put, get, exists, delete, register_dataset)
- LocalStorage implementation with hierarchical directory structure {hash[:2]}/{hash[2:4]}/{full_hash}
- Configuration loading from config.toml
- Storage path resolution priority (CAST_STORE env var, config file, default)
- Reference counting for garbage collection support
- Unit and integration tests

### 1.7 SQLite Schema and Basic Operations
Design and implement SQLite metadata database:
- Schema with tables: objects (hash, size, refs, metadata), datasets (name, version, manifest_hash), transformations (input→output mappings)
- db.rs module with SQLite operations
- Migration system for schema versioning
- CRUD operations for objects, datasets, transformations
- Query functions for metadata lookup
- Connection pooling and error handling
- Tests for database operations

## Phase 2: Data Management

### 2.1 Cast Fetch Command
Implement `cast fetch` command for downloading databases:
- HTTP/HTTPS download with progress indication
- FTP support for scientific database mirrors
- Resume capability for interrupted downloads
- Checksum verification
- Integration with storage backend
- Manifest generation from downloaded data

### 2.2 Cast Put/Get Commands
Implement basic storage operations:
- `cast put <file>`: Store file in CAS and return hash
- `cast get <hash>`: Retrieve file path by hash
- Batch operations for multiple files
- Progress reporting for large files
- Integration with SQLite metadata
- Error handling and validation

### 2.3 Automatic Symlink Farm Generation
Create symlink farms in /nix/store:
- Generate symlink structure from manifest
- Integrate with mkDataset derivation builder
- Handle nested directory structures
- Ensure correct permissions and ownership
- Update symlinks on manifest changes

### 2.4 Environment Variable Injection
Implement environment variable generation:
- manifestToEnv function in Nix
- Auto-generation of CAST_DATASET_<NAME> variables
- Integration with buildInputs and derivation setup hooks
- Variable naming normalization (uppercase, - → _)
- Documentation for usage patterns

### 2.5 Manifest Validation
Create manifest validation system:
- JSON schema validation against manifest-v1.json
- Hash verification for referenced content
- Dependency graph validation
- Size and metadata consistency checks
- Validation CLI command and library function
- Clear error messages for validation failures

## Phase 3: Transformation Pipeline

### 3.1 Cast.lib.transform Implementation
Implement the transformation pipeline system:
- Nix function for defining transformations
- CAST_OUTPUT environment variable handling
- Builder script execution
- Output hashing and CAS storage
- Manifest generation for transformed data
- Integration with existing datasets

### 3.2 Transformation Caching
Add caching for transformation results:
- SQLite table for transformation cache
- Cache key generation from inputs and transformation definition
- Cache invalidation on input changes
- Nix-level caching integration
- Performance optimization for repeated transformations

### 3.3 Dependency Graph Tracking
Implement transformation dependency tracking:
- Track input→output relationships in SQLite
- Provenance chain in manifests
- Rebuild propagation on upstream changes
- Visualization of transformation graphs
- Circular dependency detection

### 3.4 Common Transformations Library
Create library of common database transformations:
- Extract: Archive extraction (tar.gz, zip, etc.)
- MMseqs: Convert FASTA to MMseqs database format
- BLAST: Create BLAST databases
- Index: Generate various index formats
- Filter: Subset operations
- Documentation and examples for each transformation

## Phase 4: Advanced Features

### 4.1 Garbage Collection
Implement `cast gc` command:
- Reference counting based on SQLite refs
- Safe deletion of unreferenced objects
- Dry-run mode for safety
- Configurable retention policies (min_free_space, keep_recent_days)
- Integration with Nix garbage collection
- Reporting of reclaimed space

### 4.2 Multi-Storage Backend Support
Extend storage system for multiple backends:
- TieredStorage: Hot (SSD) / Cold (HDD) storage
- RemoteStorage: HTTP/S3 backends
- Storage migration between tiers
- Configurable tier policies
- Transparent access across backends
- Performance optimization for each backend type

### 4.3 NixOS Module
Create NixOS system module:
- System-wide CAST configuration
- Service for shared CAS store
- User access control
- Automatic garbage collection as systemd service
- Integration with system /nix/store
- Documentation and examples

### 4.4 Remote Registry Synchronization
Implement registry sync between machines:
- Registry protocol definition
- Push/pull operations for manifests
- Incremental updates
- Conflict resolution
- Authentication and authorization
- Mirroring for lab networks

### 4.5 Web UI for Database Browsing
Create web interface for database exploration:
- Browse available datasets
- View manifest contents
- Search by metadata
- Transformation graph visualization
- Download/export functionality
- REST API backend
- Documentation for deployment

## Development Requirements

### Testing Strategy
- Unit tests for all Rust modules
- Integration tests with temporary CAST stores
- Nix evaluation tests in flake.nix checks
- Example projects as end-to-end tests
- CI/CD pipeline integration

### Code Quality Standards
- Rust: cargo fmt, cargo clippy compliance
- Nix: Follow nixpkgs conventions, include docstrings
- Error handling: anyhow for CLI, thiserror for libraries
- Logging: tracing framework with structured logging
- Documentation: Comprehensive README and API docs

### Configuration System
- Storage configuration via config.toml
- Environment variables for overrides
- Flake attributes for defaults
- Clear precedence order
- Validation and helpful error messages

## Success Criteria

### Phase 1 Success
- Project builds with `nix build`
- Rust CLI compiles and runs basic commands
- Can store and retrieve files via BLAKE3 hashing
- SQLite metadata tracks objects correctly
- Example manifests validate against schema

### Phase 2 Success
- Can download real scientific databases
- Symlink farms appear in /nix/store correctly
- Environment variables work in derivations
- Manifests pass validation checks
- Basic workflows documented with examples

### Phase 3 Success
- Can transform FASTA to MMseqs format
- Transformations cache properly
- Dependency graph tracks lineage
- Common transformations library usable
- Transformation examples work end-to-end

### Phase 4 Success
- Garbage collection reclaims space safely
- Multi-tier storage works transparently
- NixOS module deployable system-wide
- Registry sync works between machines
- Web UI accessible and functional

## Technical Constraints

- Must integrate seamlessly with Nix ecosystem
- Must handle multi-gigabyte files efficiently
- Must ensure reproducibility and determinism
- Must support incremental updates
- Must be usable by scientists without deep Nix knowledge
- Must scale to hundreds of databases
