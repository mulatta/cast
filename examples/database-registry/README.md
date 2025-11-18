# Database Registry with flake-parts Options

This example demonstrates how to use flake-parts' options system to create a type-safe, configurable database registry with CAST.

## Features

- **Type-checked Configuration**: Uses `lib.types.submodule` for schema validation
- **Centralized Settings**: All CAST configuration managed through `config.cast` options
- **Transformation Pipelines**: Built-in examples of converting databases to different formats
- **Override Support**: Downstream consumers can customize configuration via module system
- **Pure & Reproducible**: No environment variables, all config in flake.nix

## Architecture

### Options Schema

```nix
options.cast = lib.mkOption {
  type = lib.types.submodule {
    options = {
      storePath = lib.mkOption {
        type = lib.types.str;
        description = "CAST storage root directory";
      };

      preferredDownloader = lib.mkOption {
        type = lib.types.enum ["aria2c" "curl" "wget" "auto"];
        default = "auto";
        description = "Preferred download tool";
      };
    };
  };
};
```

### Configuration

```nix
config.cast = {
  storePath = "/data/lab-databases";
  preferredDownloader = "aria2c";
};
```

### Usage in perSystem

```nix
perSystem = { config, pkgs, ... }: let
  castLib = inputs.cast.lib.configure config.cast;
in {
  packages.ncbi-nr = castLib.mkDataset {
    name = "ncbi-nr";
    version = "2024-01-15";
    manifest = ./manifests/ncbi-nr.json;
  };
};
```

## Quick Start

### 1. Build a Database

```bash
# Build NCBI NR database
nix build .#ncbi-nr

# Build UniProt database
nix build .#uniprot
```

### 2. Build Transformed Versions

```bash
# Convert to MMseqs2 format
nix build .#ncbi-nr-mmseqs

# Convert to BLAST format
nix build .#uniprot-blast
```

### 3. Development Shell

```bash
# Enter shell with databases available
nix develop

# Inside the shell:
echo $CAST_DATASET_NCBI_NR
echo $CAST_DATASET_UNIPROT
```

## Adding New Databases

### Step 1: Create Manifest

Create `manifests/new-db.json`:

```json
{
  "schema_version": "1.0",
  "dataset": {
    "name": "new-db",
    "version": "2024-01",
    "description": "My new database"
  },
  "source": {
    "url": "https://example.com/db.tar.gz",
    "download_date": "2024-01-20T10:00:00Z",
    "archive_hash": "blake3:..."
  },
  "contents": [
    {
      "path": "data.fasta",
      "hash": "blake3:...",
      "size": 12345
    }
  ]
}
```

### Step 2: Add to packages

In `flake.nix`:

```nix
perSystem = { config, ... }: {
  packages = {
    # ... existing packages ...

    new-db = castLib.mkDataset {
      name = "new-db";
      version = "2024-01";
      manifest = ./manifests/new-db.json;
    };
  };
};
```

### Step 3: Build

```bash
nix build .#new-db
```

## Creating Transformations

### Example: Custom Transformation

```nix
my-db-custom = castLib.transform {
  name = "my-db-custom";
  src = config.packages.my-db;

  builder = pkgs.writeShellScript "custom-transform" ''
    # Input available at $SOURCE_DATA
    # Output to $CAST_OUTPUT

    echo "Processing data from $SOURCE_DATA"

    # Your transformation logic here
    my-tool --input "$SOURCE_DATA" --output "$CAST_OUTPUT"

    echo "Transformation complete"
  '';
};
```

### Common Transformation Patterns

#### MMseqs2 Database

```nix
db-mmseqs = castLib.transform {
  name = "db-mmseqs";
  src = config.packages.source-db;

  builder = pkgs.writeShellScript "to-mmseqs" ''
    fasta=$(find "$SOURCE_DATA" -name "*.fasta" | head -1)
    ${pkgs.mmseqs2}/bin/mmseqs createdb "$fasta" "$CAST_OUTPUT/db"
    ${pkgs.mmseqs2}/bin/mmseqs createindex "$CAST_OUTPUT/db" "$CAST_OUTPUT/tmp"
  '';
};
```

#### BLAST Database

```nix
db-blast = castLib.transform {
  name = "db-blast";
  src = config.packages.source-db;

  builder = pkgs.writeShellScript "to-blast" ''
    fasta=$(find "$SOURCE_DATA" -name "*.fasta" | head -1)
    ${pkgs.blast}/bin/makeblastdb \
      -in "$fasta" \
      -dbtype prot \
      -out "$CAST_OUTPUT/blastdb"
  '';
};
```

## Override Pattern for Downstream Consumers

If you're using this database registry in another project, you can override the configuration:

### Create a Consumer Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    databases.url = "github:mylab/database-registry";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # Import the database registry module
      imports = [
        inputs.databases.flakeModules.default or {}
      ];

      # Override CAST configuration
      config.cast = {
        storePath = "/scratch/my-cast-store";
        preferredDownloader = "wget";
      };

      perSystem = { config, ... }: {
        packages.my-analysis = pkgs.mkShell {
          buildInputs = [
            # Use databases with custom configuration
            inputs.databases.packages.${config.system}.ncbi-nr
          ];
        };
      };
    };
}
```

## Configuration Reference

### storePath

**Type**: `string`
**Required**: Yes
**Description**: Root directory where CAST stores database files

**Example**:
```nix
config.cast.storePath = "/data/lab-databases";
```

**Note**: This path must be writable by the user running Nix builds. In production, consider:
- Using a shared network filesystem for multi-user labs
- Setting up proper permissions (e.g., group-writable)
- Regular backups of this directory

### preferredDownloader

**Type**: `enum ["aria2c" "curl" "wget" "auto"]`
**Default**: `"auto"`
**Description**: Preferred tool for downloading databases

**Options**:
- `"aria2c"`: Fastest, supports parallel downloads (recommended for large databases)
- `"curl"`: Widely available, good for most use cases
- `"wget"`: Traditional choice, very reliable
- `"auto"`: Automatically selects the best available tool

## Benefits of This Pattern

### 1. Type Safety

Invalid configurations are caught at evaluation time:

```nix
# ❌ This will fail: invalid downloader
config.cast.preferredDownloader = "invalid";

# ✅ This works
config.cast.preferredDownloader = "aria2c";
```

### 2. Self-Documenting

Options include descriptions visible via:

```bash
nix flake show
nix eval .#config.cast --json | jq
```

### 3. Natural Override

Module system automatically merges configurations from different sources.

### 4. No Environment Variables

Everything is pure and reproducible:

```bash
# ❌ Old way (impure)
CAST_STORE=/data nix build --impure

# ✅ New way (pure)
nix build  # Configuration in flake.nix
```

## Troubleshooting

### Error: "CAST storePath not configured"

**Cause**: The `config.cast.storePath` option is not set.

**Solution**: Add to your flake.nix:

```nix
config.cast.storePath = "/your/path/here";
```

### Error: Type mismatch

**Cause**: Option value doesn't match the expected type.

**Solution**: Check the type requirements in the error message. For example:

```nix
# ❌ Wrong: storePath must be a string
config.cast.storePath = /data/cast;

# ✅ Correct
config.cast.storePath = "/data/cast";
```

### Build fails with "No FASTA file found"

**Cause**: Transformation expects FASTA files but manifest doesn't include any.

**Solution**: Ensure your manifest's `contents` array includes `.fasta` or `.fa` files:

```json
{
  "contents": [
    {
      "path": "database.fasta",
      "hash": "blake3:...",
      "size": 12345
    }
  ]
}
```

## Best Practices

### 1. Version Your Manifests

Keep historical manifests for reproducibility:

```
manifests/
  ncbi-nr-2024-01-15.json
  ncbi-nr-2024-02-01.json
  ncbi-nr-2024-03-01.json
```

### 2. Use Meaningful Names

```nix
# ❌ Unclear
packages.db1 = ...;

# ✅ Clear
packages.ncbi-nr-2024-01-15 = ...;
```

### 3. Document Custom Transformations

Add comments explaining what each transformation does:

```nix
# Convert to MMseqs2 format for fast similarity searches
# Requires: mmseqs2 package
# Output: db.mmseqs (MMseqs2 database)
db-mmseqs = castLib.transform { ... };
```

### 4. Test Incrementally

Test databases individually before building transformations:

```bash
# Step 1: Test base database
nix build .#ncbi-nr

# Step 2: Test transformation
nix build .#ncbi-nr-mmseqs
```

## Next Steps

- See [../../README.md](../../README.md) for CAST library documentation
- See [../../CLAUDE.md](../../CLAUDE.md) for detailed architecture
- See [../transformation/](../transformation/) for more transformation examples
- See [../../lib/](../../lib/) for available CAST functions

## Related Examples

- [simple-dataset](../simple-dataset/) - Basic dataset example
- [transformation](../transformation/) - Transformation pipeline examples
- [registry](../registry/) - Multi-version database registry

## License

Same as CAST project (MIT)
