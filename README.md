# CAST: Content-Addressed Storage Tool

A Nix-integrated content-addressed storage system for managing large-scale scientific databases with reproducibility and version control.

## Overview

CAST solves the challenge of managing large biological databases (NCBI, UniProt, Pfam, etc.) in reproducible scientific workflows:

- **Problem**: Multi-gigabyte databases lack proper version management and storing them in `/nix/store` is impractical
- **Solution**: Content-addressed storage (CAS) for data + Nix derivations for metadata = reproducible database management

### Key Features

- **Content-Addressed Storage**: BLAKE3-based deduplication and integrity verification
- **Nix Integration**: Databases as Nix flake inputs with full dependency tracking
- **Transformation Pipelines**: Reproducible data transformations with provenance tracking
- **Version Management**: Multi-version database registries with easy version pinning
- **Space Efficient**: Deduplication across dataset versions
- **Reproducible**: Immutable datasets with cryptographic hashes

## Quick Start

### Installation

Add CAST as a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cast.url = "github:yourusername/cast";
  };
  
  outputs = { self, nixpkgs, cast }: {
    # Your packages here
  };
}
```

Build the CLI tool:

```bash
nix build github:yourusername/cast#cast-cli
./result/bin/cast-cli --version
```

### Basic Usage

1. **Create a dataset manifest** (`my-dataset-manifest.json`):

```json
{
  "schema_version": "1.0",
  "dataset": {
    "name": "my-dataset",
    "version": "1.0.0",
    "description": "My example dataset"
  },
  "source": {
    "url": "https://example.com/data.tar.gz",
    "archive_hash": "blake3:..."
  },
  "contents": [
    {
      "path": "data.txt",
      "hash": "blake3:...",
      "size": 12345,
      "executable": false
    }
  ],
  "transformations": []
}
```

2. **Store files in CAST**:

```bash
# Store files (generates BLAKE3 hashes)
cast-cli put data.txt
```

3. **Create a dataset derivation**:

```nix
{
  packages.x86_64-linux.my-dataset = cast.lib.mkDataset {
    name = "my-dataset";
    version = "1.0.0";
    manifest = ./my-dataset-manifest.json;
  };
}
```

4. **Build and use**:

```bash
# Build the dataset
CAST_STORE=$HOME/.cache/cast nix build --impure .#my-dataset

# Files are available as symlinks
ls -la result/data/
cat result/data/data.txt
```

## Architecture

```
┌─────────────────────────────────────┐
│ User Projects                        │
│  - Flake inputs (database deps)     │
│  - Reproducible workflows            │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│ CAST Library (lib/*.nix)             │
│  - mkDataset                         │
│  - transform                         │
│  - fetchDatabase (future)            │
└─────────────────────────────────────┘
                ↓
┌──────────────────┬──────────────────┐
│ Metadata         │ CLI Tool         │
│ (/nix/store)     │ (cast-cli)       │
│                  │                  │
│ - manifest.json  │ - put/get        │
│ - symlink farms  │ - transform      │
│ - derivations    │ - hashing        │
└──────────────────┴──────────────────┘
                ↓
┌─────────────────────────────────────┐
│ CAS Backend ($CAST_STORE)            │
│                                      │
│ store/{hash[:2]}/{hash[2:4]}/{hash} │
│ - Actual file content                │
│ - BLAKE3 addressed                   │
│ - Deduplicated                       │
└─────────────────────────────────────┘
```

### Data Flow

1. **Files** → `cast-cli put` → **CAST store** (content-addressed)
2. **Manifest** → `cast.lib.mkDataset` → **Nix derivation** (metadata + symlinks)
3. **Source dataset** → `cast.lib.transform` → **Transformed dataset** (with provenance)

## API Reference

### `cast.lib.mkDataset`

Create a dataset derivation from a manifest.

```nix
cast.lib.mkDataset {
  name = "dataset-name";
  version = "1.0.0";
  manifest = ./manifest.json;  # Or attribute set
  storePath = null;  # Optional: override CAST_STORE
}
```

**Returns**: A Nix derivation with:
- `/data/` - Symlinks to files in CAST store
- `/manifest.json` - Dataset manifest
- Environment variables: `$CAST_DATASET_<NAME>`, `$CAST_DATASET_<NAME>_VERSION`

**Example**:

```nix
let
  ncbiNr = cast.lib.mkDataset {
    name = "ncbi-nr";
    version = "2024-01-15";
    manifest = ./ncbi-nr-manifest.json;
  };
in
pkgs.mkShell {
  buildInputs = [ ncbiNr ];
  # $CAST_DATASET_NCBI_NR now points to dataset
}
```

### `cast.lib.transform`

Transform a dataset with a builder script.

```nix
cast.lib.transform {
  name = "transformation-name";
  src = sourceDataset;  # Input dataset
  builder = ''
    # Bash script with access to:
    # $SOURCE_DATA - input files
    # $CAST_OUTPUT - output directory
    
    process-data "$SOURCE_DATA"/* > "$CAST_OUTPUT/result.txt"
  '';
  params = {};  # Optional transformation parameters
}
```

**Returns**: A dataset derivation with transformed data and provenance chain.

**Example**:

```nix
let
  rawData = cast.lib.mkDataset {...};
  
  processedData = cast.lib.transform {
    name = "filter-large-files";
    src = rawData;
    params = { minSize = 10000; };
    
    builder = ''
      MIN=$(echo "$CAST_TRANSFORM_PARAMS" | jq -r '.minSize')
      for file in "$SOURCE_DATA"/*; do
        if [ $(stat -c%s "$file") -ge $MIN ]; then
          cp "$file" "$CAST_OUTPUT/"
        fi
      done
    '';
  };
in processedData
```

### `cast.lib.symlinkSubset` (Future)

Create a subset of datasets with selected files.

```nix
cast.lib.symlinkSubset {
  name = "subset-name";
  paths = [
    { name = "ncbi"; path = datasets.ncbi-nr; }
    { name = "uniprot"; path = datasets.uniprot; }
  ];
}
```

### `cast.lib.fetchDatabase` (Future)

Download and register a database.

```nix
cast.lib.fetchDatabase {
  name = "ncbi-nr";
  url = "ftp://ftp.ncbi.nlm.nih.gov/blast/db/nr.tar.gz";
  hash = "blake3:...";  # Optional verification
  extract = true;
}
```

## Examples

### Simple Dataset

See [`examples/simple-dataset/`](examples/simple-dataset/) for a basic example with sample data files.

```bash
cd examples/simple-dataset
CAST_STORE=$HOME/.cache/cast nix build --impure .#example-dataset
```

### Transformations

See [`examples/transformation/`](examples/transformation/) for transformation pipeline examples:

- File copy transformation
- Text processing (uppercase)
- Chained transformations with provenance

```bash
cd examples/transformation
CAST_STORE=$HOME/.cache/cast nix build --impure .#example-chain
cat result/manifest.json | jq '.transformations'
```

### Database Registry

See [`examples/registry/`](examples/registry/) for multi-version database management:

```bash
cd examples/registry
CAST_STORE=$HOME/.cache/cast nix build --impure .#test-db-latest
nix develop .#legacy  # Use older version
```

## CLI Reference

### `cast-cli put`

Store a file in CAST and return its hash:

```bash
cast-cli put /path/to/file
# Output: blake3:abc123...
```

### `cast-cli get`

Retrieve the path to a file by hash:

```bash
cast-cli get blake3:abc123...
# Output: /home/user/.cache/cast/store/ab/c1/abc123...
```

### `cast-cli transform`

Generate transformation manifest (used by `cast.lib.transform`):

```bash
cast-cli transform \
  --input-manifest source-manifest.json \
  --output-dir ./output \
  --transform-type my-transform
```

## Configuration

### Storage Location

CAST store location (priority order):

1. `$CAST_STORE` environment variable
2. Flake `storePath` parameter
3. `~/.config/cast/config.toml`
4. Default: `~/.cache/cast`

### Environment Variables

- `CAST_STORE` - Override default storage location
- `CAST_DATASET_<NAME>` - Auto-set by datasets (points to `/data`)
- `CAST_DATASET_<NAME>_VERSION` - Dataset version
- `CAST_DATASET_<NAME>_MANIFEST` - Path to manifest

## Use Cases

### Bioinformatics Pipeline

```nix
{
  inputs.databases.url = "git+ssh://lab-server/databases";
  
  outputs = { self, nixpkgs, databases }: {
    packages.x86_64-linux.analysis = pkgs.mkDerivation {
      name = "protein-analysis";
      buildInputs = [
        databases.databases.ncbi-nr."2024-01-15"
        databases.databases.uniprot."2024.01"
        pkgs.mmseqs2
      ];
      
      buildPhase = ''
        mmseqs search \
          query.fasta \
          "$CAST_DATASET_NCBI_NR/nr" \
          results.tsv
      '';
    };
  };
}
```

### Reproducible Research

```nix
# Pin exact database versions for reproducibility
{
  packages.analysis-v1 = mkAnalysis {
    databases = {
      ncbi = dbs.ncbi-nr."2024-01-15";  # Specific version
      uniprot = dbs.uniprot."2024.01";
    };
  };
}
```

### Database Transformations

```nix
# Convert NCBI to MMseqs format
let
  ncbiRaw = cast.lib.mkDataset {...};
  ncbiMmseqs = cast.lib.transform {
    name = "ncbi-to-mmseqs";
    src = ncbiRaw;
    builder = ''
      ${pkgs.mmseqs2}/bin/mmseqs createdb \
        "$SOURCE_DATA/nr.fasta" \
        "$CAST_OUTPUT/nr_mmseqs"
    '';
  };
in ncbiMmseqs
```

## Design Decisions

See [`CLAUDE.md`](CLAUDE.md) for detailed architecture decisions:

- Why BLAKE3 for hashing
- Why separate data from metadata
- Why Nix integration
- Storage format rationale

## Development

### Project Structure

```
cast/
├── lib/                  # Nix library functions
│   ├── mkDataset.nix
│   ├── transform.nix
│   └── ...
├── packages/
│   └── cast-cli/        # Rust CLI tool
├── examples/            # Usage examples
│   ├── simple-dataset/
│   ├── transformation/
│   └── registry/
└── schemas/             # JSON schemas
    └── manifest-v1.json
```

### Building from Source

```bash
# Clone repository
git clone https://github.com/yourusername/cast
cd cast

# Build CLI tool
nix build .#cast-cli

# Run tests
nix flake check

# Development shell
nix develop
```

### Running Tests

```bash
# Rust tests
cd packages/cast-cli
cargo test

# Integration tests
nix build .#checks.x86_64-linux.test-mkDataset
nix build .#checks.x86_64-linux.test-transform
```

## Roadmap

### Phase 1: MVP ✓
- [x] Core library functions (`mkDataset`, `transform`)
- [x] BLAKE3 hashing
- [x] Local storage backend
- [x] Basic CLI (`put`, `get`, `transform`)
- [x] Transformation provenance tracking

### Phase 2: Database Management (Future)
- [ ] `fetchDatabase` implementation
- [ ] Automatic manifest generation
- [ ] Archive extraction
- [ ] HTTP/FTP download support

### Phase 3: Advanced Features (Future)
- [ ] Garbage collection
- [ ] Multi-tier storage (SSD/HDD)
- [ ] Remote storage backends
- [ ] Web UI for dataset browsing
- [ ] NixOS module

## Contributing

Contributions welcome! Please:

1. Follow Nix code style conventions
2. Add tests for new features
3. Update documentation
4. Run `nix fmt` before committing

## License

[License TBD]

## Citation

If you use CAST in your research, please cite:

```
[Citation TBD]
```

## Related Projects

- [Nix](https://nixos.org/) - Reproducible package management
- [IPFS](https://ipfs.io/) - Content-addressed storage
- [Git LFS](https://git-lfs.github.com/) - Large file storage for Git
- [Bazel](https://bazel.build/) - Build system with content addressing

## Contact

- Issues: https://github.com/yourusername/cast/issues
- Discussions: https://github.com/yourusername/cast/discussions

---

Built with ❤️ for reproducible science
