# Bioinformatics Transformation Builders Examples

This example demonstrates CAST's built-in transformation builders for common bioinformatics database formats.

## Overview

CAST provides pre-built transformation functions for converting FASTA protein/nucleotide sequences into formats required by popular bioinformatics tools:

- **MMseqs2**: Ultra-fast sequence search and clustering
- **BLAST**: Traditional sequence alignment search
- **Diamond**: Accelerated protein sequence alignment
- **Archive extraction**: Handling compressed databases

## Quick Start

```bash
# Build MMseqs2 database example
nix build .#example-mmseqs

# Build BLAST database example
nix build .#example-blast-prot

# Build Diamond database example
nix build .#example-diamond

# Build extraction example
nix build .#example-extract

# Build multi-format example (all three formats)
nix build .#example-all-formats

# Build pipeline example (extract → MMseqs2)
nix build .#example-pipeline
```

## Examples

### Example 1: MMseqs2 Database

Converts FASTA protein sequences to MMseqs2 database format with index:

```nix
example-mmseqs = castLib.toMMseqs {
  name = "sample-proteins-mmseqs";
  src = sampleFastaDataset;
  fastaFile = "proteins.fasta";
  createIndex = true;  # Create search index
};
```

**Output**: MMseqs2 database files (`db`, `db.index`, etc.)

**Use case**: Fast protein searches with MMseqs2

### Example 2: BLAST Database

Converts FASTA to BLAST database format:

```nix
example-blast-prot = castLib.toBLAST {
  name = "sample-proteins-blast";
  src = sampleFastaDataset;
  fastaFile = "proteins.fasta";
  dbType = "prot";           # "prot" or "nucl"
  title = "Sample Protein Database";
  parseSeqids = true;        # Parse sequence identifiers
};
```

**Output**: BLAST database files (`.phr`, `.pin`, `.psq`)

**Use case**: Traditional BLAST searches

### Example 3: Diamond Database

Converts FASTA to Diamond database format:

```nix
example-diamond = castLib.toDiamond {
  name = "sample-proteins-diamond";
  src = sampleFastaDataset;
  fastaFile = "proteins.fasta";
  # Optional taxonomy parameters:
  # taxonmap = "prot.accession2taxid.gz";
  # taxonnodes = "nodes.dmp";
  # taxonnames = "names.dmp";
};
```

**Output**: Diamond database file (`.dmnd`)

**Use case**: Ultra-fast protein alignment (up to 20,000x faster than BLAST)

### Example 4: Archive Extraction

Extract common archive formats:

```nix
example-extract = castLib.extractArchive {
  name = "sample-extracted";
  src = sampleArchiveDataset;
  archiveFile = "proteins.tar.gz";
  stripComponents = 0;  # Number of leading path components to strip
};
```

**Supported formats**:
- `.tar.gz`, `.tgz`
- `.tar.bz2`
- `.tar.xz`
- `.zip`

**Use case**: Extracting downloaded database archives before conversion

### Example 5: Transformation Pipeline

Chain transformations together:

```nix
example-pipeline = let
  # Step 1: Extract archive
  extracted = castLib.extractArchive {
    name = "pipeline-extracted";
    src = sampleArchiveDataset;
    archiveFile = "proteins.tar.gz";
    stripComponents = 1;
  };

  # Step 2: Convert to MMseqs2
  mmseqsDb = castLib.toMMseqs {
    name = "pipeline-mmseqs";
    src = extracted;
    fastaFile = "sequences.fasta";
    createIndex = false;
  };
in
  mmseqsDb;
```

**Use case**: Multi-step data processing workflows

### Example 6: Multi-Format Export

Create all formats from a single source:

```nix
example-all-formats = castLib.symlinkSubset {
  name = "sample-all-formats";
  paths = [
    { name = "mmseqs"; path = example-mmseqs; }
    { name = "blast"; path = example-blast-prot; }
    { name = "diamond"; path = example-diamond; }
  ];
};
```

**Use case**: Support multiple tools without redundant conversions

## Builder Reference

### `castLib.toMMseqs`

Convert FASTA to MMseqs2 database format.

**Parameters**:
- `name` (string): Output dataset name
- `src` (dataset): Source dataset with FASTA file(s)
- `fastaFile` (string, optional): FASTA filename (auto-detected if only one)
- `createIndex` (bool, default: `true`): Create search index
- `indexParams` (string, default: `""`): Additional indexing parameters

**Auto-detection**: If `fastaFile` is not specified, searches for files with extensions: `.fasta`, `.fa`, `.faa`

### `castLib.toBLAST`

Convert FASTA to BLAST database format.

**Parameters**:
- `name` (string): Output dataset name
- `src` (dataset): Source dataset with FASTA file(s)
- `fastaFile` (string, optional): FASTA filename
- `dbType` (string, default: `"prot"`): Database type - `"prot"` or `"nucl"`
- `parseSeqids` (bool, default: `true`): Parse sequence identifiers
- `title` (string, default: `name`): Database title
- `extraArgs` (string, default: `""`): Additional makeblastdb arguments

**Auto-detection**: Searches for `.fasta`, `.fa`, `.faa`, `.fna` files

### `castLib.toDiamond`

Convert FASTA to Diamond database format.

**Parameters**:
- `name` (string): Output dataset name
- `src` (dataset): Source dataset with FASTA file(s)
- `fastaFile` (string, optional): FASTA filename
- `taxonmap` (string, optional): Taxonomy mapping file
- `taxonnodes` (string, optional): Taxonomy nodes file
- `taxonnames` (string, optional): Taxonomy names file
- `extraArgs` (string, default: `""`): Additional makedb arguments

**Auto-detection**: Searches for `.fasta`, `.fa`, `.faa` files

### `castLib.extractArchive`

Extract common archive formats.

**Parameters**:
- `name` (string): Output dataset name
- `src` (dataset): Source dataset with archive file(s)
- `archiveFile` (string, optional): Archive filename
- `stripComponents` (int, default: `0`): Strip N leading path components

**Supported formats**: `.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, `.zip`

## Development Workflow

### Interactive Development

```bash
# Enter shell with all tools
nix develop

# Enter shell with MMseqs2 database loaded
nix develop .#with-mmseqs

# Test database
mmseqs search example.fasta $CAST_DATASET_SAMPLE_PROTEINS_MMSEQS/db result.m8 tmp/
```

### Real-World Example: NCBI NR Database

```nix
{
  packages = let
    # Download NCBI NR (in practice)
    ncbiNrRaw = castLib.mkDataset {
      name = "ncbi-nr-raw";
      version = "2024-01";
      manifest = ./ncbi-nr-manifest.json;
    };

    # Create all three formats
    ncbiNrMmseqs = castLib.toMMseqs {
      name = "ncbi-nr-mmseqs";
      src = ncbiNrRaw;
      fastaFile = "nr.fasta";
    };

    ncbiNrBlast = castLib.toBLAST {
      name = "ncbi-nr-blast";
      src = ncbiNrRaw;
      fastaFile = "nr.fasta";
      dbType = "prot";
      title = "NCBI Non-Redundant Protein Database";
    };

    ncbiNrDiamond = castLib.toDiamond {
      name = "ncbi-nr-diamond";
      src = ncbiNrRaw;
      fastaFile = "nr.fasta";
    };
  in {
    inherit ncbiNrMmseqs ncbiNrBlast ncbiNrDiamond;

    # Unified access to all formats
    ncbi-nr-all = castLib.symlinkSubset {
      name = "ncbi-nr-all-formats";
      paths = [
        { name = "mmseqs"; path = ncbiNrMmseqs; }
        { name = "blast"; path = ncbiNrBlast; }
        { name = "diamond"; path = ncbiNrDiamond; }
      ];
    };
  };
}
```

## Provenance Tracking

All builders automatically track transformation metadata:

```json
{
  "transformations": [
    {
      "type": "transform",
      "from": "blake3:source_hash...",
      "params": {
        "fastaFile": "proteins.fasta",
        "createIndex": true,
        "tool": "mmseqs2",
        "version": "15.6f452"
      }
    }
  ]
}
```

This ensures:
- Full reproducibility (exact tool versions recorded)
- Transformation chain visibility
- Debugging support (know which tools produced which outputs)

## Performance Considerations

### MMseqs2 vs BLAST vs Diamond

| Tool | Speed | Sensitivity | Memory |
|------|-------|-------------|---------|
| MMseqs2 | Fast | High | Medium |
| Diamond | Very Fast | High | Low |
| BLAST | Slow | High | Medium |

**Recommendation**:
- Use **Diamond** for routine protein searches (fastest)
- Use **MMseqs2** for clustering and sensitive searches
- Use **BLAST** for compatibility with existing workflows

### Index Creation

```nix
# With index (slower build, faster searches)
toMMseqs { createIndex = true; }

# Without index (faster build, slower searches)
toMMseqs { createIndex = false; }
```

Create indexes for databases used frequently in production.

## Testing

```bash
# Verify all examples build
nix flake check

# Build specific example
nix build .#example-mmseqs

# Check output
ls -lh result/data/
```

## Next Steps

- See [`examples/database-registry`](../database-registry) for managing real-world databases
- See [`examples/transformation`](../transformation) for custom transformations
- See main [README](../../README.md) for CAST overview

## References

- [MMseqs2 Documentation](https://github.com/soedinglab/MMseqs2)
- [BLAST+ Documentation](https://www.ncbi.nlm.nih.gov/books/NBK279690/)
- [Diamond Documentation](https://github.com/bbuchfink/diamond)
