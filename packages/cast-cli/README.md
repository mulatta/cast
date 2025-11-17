# cast-cli

Command-line interface for CAST (Content-Addressed Storage Tool).

## Overview

`cast-cli` is the Rust-based CLI tool for managing content-addressed storage of large scientific databases. It provides commands for storing, retrieving, and transforming datasets with BLAKE3 hashing and SQLite metadata tracking.

## Commands

### `cast put <file>`
Store a file in the content-addressed storage and return its BLAKE3 hash.

### `cast get <hash>`
Retrieve the path to a file by its BLAKE3 hash.

### `cast fetch <url> [--hash <hash>]`
Download and register a database from a URL, optionally verifying its hash.

### `cast transform --input-manifest <path> --output-dir <dir> --transform-type <type>`
Transform a dataset using the specified transformation type.

### `cast gc [--dry-run]`
Run garbage collection to remove unreferenced objects.

## Building

```bash
cargo build --release
```

## Testing

```bash
cargo test
```

## Environment Variables

- `CAST_STORE`: Override the CAS storage root path
- `CAST_CONFIG`: Override the config file location
- `CAST_LOG`: Set log level (error/warn/info/debug/trace)

## Development Status

This is currently a stub implementation. Features will be implemented in phases:
- **Phase 1 (Task 4-7)**: Core functionality (hashing, storage, database)
- **Phase 2**: Data management (fetch, put/get commands)
- **Phase 3**: Transformation pipeline
- **Phase 4**: Advanced features (garbage collection, multi-backend)
