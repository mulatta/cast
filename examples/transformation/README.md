# Transformation Example

This example demonstrates data transformation using CAST's transformation pipeline.

## Overview

Shows how to:
- Download a database with `cast.lib.fetchDatabase`
- Transform data using `cast.lib.transform`
- Chain multiple transformations
- Use the transformed dataset in a development shell

## Example Workflow

1. **Fetch**: Download NCBI database archive
2. **Extract**: Unpack the archive
3. **Transform**: Convert to MMseqs2 database format
4. **Use**: Access in development environment

## Files (to be implemented in task 10)

- `flake.nix`: Complete transformation pipeline example
- Example transformations:
  - Archive extraction (tar.gz → files)
  - Format conversion (FASTA → MMseqs2)
  - Indexing operations

## Usage

```bash
# Build the transformation pipeline
nix build .#ncbi-mmseqs

# Enter development shell with transformed database
nix develop
```

## Implementation Status

⏳ **Pending** - Will be implemented in task 10 (Example and Documentation)

Transformation pipeline itself will be implemented in task 9.
