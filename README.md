# CAST: Content-Addressed Storage Tool

> **📘 For Claude Code users**: See [`.claude/CLAUDE.md`](.claude/CLAUDE.md) for AI assistant context and instructions.

A Nix-integrated content-addressed storage system for managing large-scale scientific databases with reproducibility and version control.

## Overview

CAST solves the challenge of managing large biological databases (NCBI, UniProt, Pfam, etc.) in reproducible scientific workflows:

- **Problem**: Multi-gigabyte databases lack proper version management and storing them in `/nix/store` is impractical
- **Solution**: Content-addressed storage (CAS) for data + Nix derivations for metadata = reproducible database management

### Key Features

- **Pure Configuration**: Zero environment variables required, all configuration in Nix
- **Content-Addressed Storage**: BLAKE3-based deduplication and integrity verification
- **Nix Integration**: Databases as Nix flake inputs with full dependency tracking
- **Transformation Pipelines**: Reproducible data transformations with provenance tracking
- **Version Management**: Multi-version database registries with easy version pinning
- **Space Efficient**: Deduplication across dataset versions
- **Type-Safe**: All configuration validated at Nix evaluation time

## Quick Start

### Installation

Add CAST as a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
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
./result/bin/cast --version
```

### Basic Usage

1. **Configure CAST library** in your flake:

```nix
{
  outputs = { self, nixpkgs, cast }: let
    # Configure CAST with explicit storage path
    castLib = cast.lib.configure {
      storePath = "/data/lab-databases";
    };
  in {
    packages.x86_64-linux = {
      # Use configured library
      my-dataset = castLib.mkDataset {
        name = "my-dataset";
        version = "1.0.0";
        manifest = ./my-dataset-manifest.json;
      };
    };
  };
}
```

2. **Create a dataset manifest** (`my-dataset-manifest.json`):

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

3. **Build and use**:

```bash
# Build the dataset (pure evaluation!)
nix build .#my-dataset

# Files are available as symlinks
ls -la result/data/
cat result/data/data.txt
```

## Architecture

```
┌─────────────────────────────────────┐
│ User Projects                        │
│  - Flake inputs (database deps)     │
│  - Pure configuration                │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│ CAST Library (lib/*.nix)             │
│  - configure                         │
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
│ CAS Backend (configured storePath)   │
│                                      │
│ store/{hash[:2]}/{hash[2:4]}/{hash} │
│ - Actual file content                │
│ - BLAKE3 addressed                   │
│ - Deduplicated                       │
└─────────────────────────────────────┘
```

### Data Flow

1. **Files** → `cast put` → **CAST store** (content-addressed)
2. **Manifest** + **Configuration** → `castLib.mkDataset` → **Nix derivation** (pure)
3. **Source dataset** → `castLib.transform` → **Transformed dataset** (with provenance)

## API Reference

### `cast.lib.configure`

Create a configured CAST library instance.

```nix
castLib = cast.lib.configure {
  storePath = "/data/cast-store";  # Required: where to store data
  # Future options:
  # preferredDownloader = "aria2c";
  # compressionLevel = 9;
}
```

**Parameters**:
- `storePath` (string, required): Path to CAST storage directory

**Returns**: Configured library instance with all CAST functions

**Example with flake-parts**:

```nix
{
  inputs.cast.url = "github:yourusername/cast";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      perSystem = {config, pkgs, ...}: let
        castLib = inputs.cast.lib.configure {
          storePath = "/data/lab-databases";
        };
      in {
        packages = {
          ncbi-nr = castLib.mkDataset {...};
          uniprot = castLib.mkDataset {...};
        };
      };
    };
}
```

### `castLib.mkDataset`

Create a dataset derivation from a manifest.

```nix
castLib.mkDataset {
  name = "dataset-name";
  version = "1.0.0";
  manifest = ./manifest.json;  # Or attribute set
  storePath = null;  # Optional: override configured storePath
}
```

**Parameters**:
- `name` (string): Dataset name (used for environment variables)
- `version` (string): Dataset version
- `manifest` (path or attrset): Dataset manifest
- `storePath` (string, optional): Override configured storage path

**Returns**: A Nix derivation with:
- `/data/` - Symlinks to files in CAST store
- `/manifest.json` - Dataset manifest
- Environment variables: `$CAST_DATASET_<NAME>`, `$CAST_DATASET_<NAME>_VERSION`

**Example**:

```nix
let
  castLib = cast.lib.configure {storePath = "/data/cast";};

  ncbiNr = castLib.mkDataset {
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

### `castLib.transform`

Transform a dataset with a builder script.

```nix
castLib.transform {
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

**Parameters**:
- `name` (string): Transformation name
- `src` (derivation): Source dataset
- `builder` (string): Bash script for transformation
- `params` (attrset, optional): Transformation parameters (passed as JSON)

**Returns**: A dataset derivation with transformed data and provenance chain.

**Example - Convert FASTA to MMseqs2**:

```nix
let
  castLib = cast.lib.configure {storePath = "/data/cast";};

  rawFasta = castLib.mkDataset {...};

  mmseqsDb = castLib.transform {
    name = "to-mmseqs";
    src = rawFasta;

    builder = ''
      ${pkgs.mmseqs2}/bin/mmseqs createdb \
        "$SOURCE_DATA/sequences.fasta" \
        "$CAST_OUTPUT/mmseqs_db"
    '';
  };
in mmseqsDb
```

### `cast.lib.symlinkSubset`

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
castLib.fetchDatabase {
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
nix build .#example-dataset  # Pure evaluation!
```

**Key pattern**:
```nix
let
  castLib = cast.lib.configure {
    storePath = builtins.getEnv "HOME" + "/.cache/cast";
  };
in {
  example-dataset = castLib.mkDataset {
    name = "simple-example";
    version = "1.0.0";
    manifest = ./manifest.json;
  };
}
```

### Transformations

See [`examples/transformation/`](examples/transformation/) for transformation pipeline examples:

- File copy transformation
- Text processing (uppercase)
- Chained transformations with provenance

```bash
cd examples/transformation
nix build .#example-chain
cat result/manifest.json | jq '.transformations'
```

### Multi-Version Database Registry

See [`examples/registry/`](examples/registry/) for multi-version database management:

```nix
databases = {
  test-db = {
    "1.0.0" = castLib.mkDataset {...};
    "1.1.0" = castLib.mkDataset {...};
    "2.0.0" = castLib.mkDataset {...};
  };
};

# Use specific version
packages.test-db-latest = databases.test-db."2.0.0";
packages.test-db-stable = databases.test-db."1.1.0";
```

```bash
cd examples/registry
nix build .#test-db-latest
nix develop .#legacy  # Use older version
```

### Production Database Registry with flake-parts

See [`examples/database-registry/`](examples/database-registry/) for production-ready pattern:

```nix
{
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      perSystem = {config, ...}: let
        castConfig = {
          storePath = "/data/lab-databases";
          preferredDownloader = "aria2c";
        };
        castLib = inputs.cast.lib.configure castConfig;
      in {
        packages = {
          ncbi-nr = castLib.mkDataset {...};
          uniprot = castLib.mkDataset {...};

          # Transformations
          ncbi-nr-mmseqs = castLib.transform {
            src = config.packages.ncbi-nr;
            builder = "...";
          };
        };
      };
    };
}
```

## CLI Reference

### `cast put`

Store a file in CAST and return its hash:

```bash
cast put /path/to/file
# Output: blake3:abc123...
```

### `cast get`

Retrieve the path to a file by hash:

```bash
cast get blake3:abc123...
# Output: /data/cast-store/store/ab/c1/abc123...
```

### `cast transform`

Generate transformation manifest (used by `castLib.transform`):

```bash
cast transform \
  --input-manifest source-manifest.json \
  --output-dir ./output \
  --transform-type my-transform
```

## Configuration

See [`CONFIGURATION.md`](CONFIGURATION.md) for detailed configuration guide.

### Quick Reference

**Pure configuration pattern** (recommended):

```nix
# In your flake.nix
let
  castLib = cast.lib.configure {
    storePath = "/data/cast-store";
  };
in {
  packages.my-db = castLib.mkDataset {...};
}
```

**Configuration priority**:

1. Explicit `storePath` parameter in `mkDataset`
2. Configuration passed to `cast.lib.configure`
3. Error with helpful message (no implicit defaults)

**Environment variables for datasets** (auto-generated):

- `CAST_DATASET_<NAME>` - Path to dataset `/data` directory
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
        databases.packages.x86_64-linux.ncbi-nr
        databases.packages.x86_64-linux.uniprot
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
let
  castLib = cast.lib.configure {storePath = "/data/cast";};

  # Original FASTA database
  ncbiRaw = castLib.mkDataset {...};

  # Convert to MMseqs format
  ncbiMmseqs = castLib.transform {
    name = "ncbi-to-mmseqs";
    src = ncbiRaw;
    builder = ''
      ${pkgs.mmseqs2}/bin/mmseqs createdb \
        "$SOURCE_DATA/nr.fasta" \
        "$CAST_OUTPUT/nr_mmseqs"
    '';
  };

  # Convert to BLAST format
  ncbiBlast = castLib.transform {
    name = "ncbi-to-blast";
    src = ncbiRaw;
    builder = ''
      ${pkgs.blast}/bin/makeblastdb \
        -in "$SOURCE_DATA/nr.fasta" \
        -dbtype prot \
        -out "$CAST_OUTPUT/nr_blast"
    '';
  };
in {
  inherit ncbiMmseqs ncbiBlast;
}
```

## Design Decisions

See [`CLAUDE.md`](CLAUDE.md) for detailed architecture decisions:

- Why BLAKE3 for hashing
- Why separate data from metadata
- Why pure configuration (no environment variables)
- Storage format rationale
- Why Nix integration

## Development

### Project Structure

```
cast/
├── lib/                  # Nix library functions
│   ├── default.nix       # Main exports + configure
│   ├── mkDataset.nix
│   ├── transform.nix
│   ├── manifest.nix
│   └── types.nix
├── packages/
│   └── cast-cli/        # Rust CLI tool
├── examples/            # Usage examples
│   ├── simple-dataset/
│   ├── transformation/
│   ├── registry/
│   └── database-registry/
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

# Run all tests
nix flake check

# Development shell with Rust tooling
nix develop
```

### Running Tests

```bash
# Nix library tests
nix build .#checks.x86_64-linux.lib-validators
nix build .#checks.x86_64-linux.integration-mkDataset-attrset

# Rust tests
cd packages/cast-cli
cargo test

# Format code
nix fmt
```

## Roadmap

### Phase 1: MVP ✅
- [x] Core library functions (`mkDataset`, `transform`)
- [x] BLAKE3 hashing
- [x] Local storage backend
- [x] Basic CLI (`put`, `get`, `transform`)
- [x] Transformation provenance tracking

### Phase 2: Pure Configuration ✅
- [x] Pure configuration pattern (`configure`)
- [x] Zero environment variables required
- [x] Type-checked configuration
- [x] cast-cli as Nix package
- [x] Complete database registry examples
- [x] Works with `nix build --pure`

### Phase 3: Database Management (In Progress)
- [ ] Common transformation builders (`toMMseqs`, `toBLAST`, `toDiamond`)
- [ ] NixOS module for system-wide database management
- [ ] Comprehensive documentation

### Phase 4: Advanced Features (Future)
- [ ] `fetchDatabase` implementation
- [ ] Automatic manifest generation
- [ ] Garbage collection
- [ ] Multi-tier storage (SSD/HDD)
- [ ] Remote storage backends
- [ ] Web UI for dataset browsing

## Contributing

Contributions welcome! Please:

1. Follow Nix code style conventions
2. Add tests for new features
3. Update documentation
4. Run `nix fmt` before committing
5. Use pure configuration patterns (no environment variables)

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
