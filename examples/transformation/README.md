# Transformation Pipeline Examples

This example demonstrates CAST's transformation pipeline capabilities, showing how to transform datasets while preserving full provenance tracking.

## Examples

### 1. Simple File Copy (`example-copy`)

Demonstrates the basic transformation structure by copying files from a source dataset.

```bash
CAST_STORE=$HOME/.cache/cast nix build --impure .#example-copy
```

**Features:**
- Simple builder script
- File inventory generation
- Transformation metadata tracking

### 2. Text Transformation (`example-uppercase`)

Shows data transformation by converting text files to uppercase.

```bash
CAST_STORE=$HOME/.cache/cast nix build --impure .#example-uppercase
```

**Output:**
```bash
cat result/data/hello.txt  # HELLO WORLD!
cat result/data/world.txt  # WORLD
```

### 3. Chained Transformations (`example-chain`)

Demonstrates transformation composition with full provenance chain preservation.

```bash
CAST_STORE=$HOME/.cache/cast nix build --impure .#example-chain
```

**Provenance chain:**
```json
{
  "transformations": [
    {"type": "copy-transform", "from": "blake3:...", "params": {}},
    {"type": "chain-uppercase", "from": "blake3:...", "params": {}}
  ]
}
```

## How Transformations Work

### 1. Define the Transformation

```nix
cast.lib.transform {
  name = "my-transform";
  src = sourceDataset;  # Input dataset
  
  builder = ''
    # Builder script has access to:
    # - $SOURCE_DATA: Input dataset files
    # - $CAST_OUTPUT: Where to write transformed files
    
    for file in "$SOURCE_DATA"/*.txt; do
      # Process files and write to CAST_OUTPUT
      process "$file" > "$CAST_OUTPUT/$(basename $file)"
    done
  '';
}
```

### 2. Automatic Processing

The transform function automatically:
- Executes the builder script
- Hashes all output files with BLAKE3
- Generates a new manifest with file inventory
- Preserves the transformation chain
- Creates the dataset derivation

### 3. Result Structure

```
/nix/store/...-cast-transform-my-transform/
├── manifest.json       # Complete manifest with provenance
├── data/              # Transformed files
│   └── ...
├── contents.json      # File inventory
└── transformations.json  # Transformation history
```

## Real-World Example Pattern

For actual database transformations:

```nix
let
  # Download NCBI database
  ncbiNr = cast.lib.fetchDatabase {
    name = "ncbi-nr";
    url = "ftp://ftp.ncbi.nlm.nih.gov/blast/db/nr.tar.gz";
    extract = true;
  };
  
  # Transform to MMseqs format
  ncbiMmseqs = cast.lib.transform {
    name = "ncbi-to-mmseqs";
    src = ncbiNr;
    
    builder = pkgs.writeShellScript "convert" ''
      ${pkgs.mmseqs2}/bin/mmseqs createdb \
        "$SOURCE_DATA/nr.fasta" \
        "$CAST_OUTPUT/nr_mmseqs"
      
      ${pkgs.mmseqs2}/bin/mmseqs createindex \
        "$CAST_OUTPUT/nr_mmseqs" \
        "$CAST_OUTPUT/tmp"
    '';
  };
in
  # Use in development shell
  pkgs.mkShell {
    buildInputs = [ pkgs.mmseqs2 ncbiMmseqs ];
  }
```

## Key Features

### Automatic Caching

Nix's content-addressed derivations provide automatic caching:
- Same inputs → cached results reused
- No manual cache management needed
- Transformation only runs when inputs change

### Provenance Tracking

Every transformation is recorded in the manifest:
- Transformation type
- Input dataset hash
- Parameters used
- Full chain preserved through multiple transformations

### Reproducibility

Transform pipelines are fully reproducible:
- Declarative Nix expressions
- Content-addressed storage
- Complete dependency tracking
- Immutable results

## Builder Script Variables

Available in all builder scripts:

- `$SOURCE_DATA` - Path to input dataset files
- `$CAST_OUTPUT` - Directory for transformation outputs
- `$CAST_TRANSFORM_NAME` - Transformation name
- `$CAST_TRANSFORM_PARAMS` - JSON parameters (if provided)

## Testing Transformations

Build and inspect the results:

```bash
# Build transformation
CAST_STORE=$HOME/.cache/cast nix build --impure .#example-uppercase

# Check manifest
cat result/manifest.json | jq .

# View transformation chain
cat result/manifest.json | jq '.transformations'

# Inspect output files
ls -la result/data/
cat result/data/*
```

## Advanced Usage

### Parameterized Transformations

```nix
cast.lib.transform {
  name = "filter-by-size";
  src = myDataset;
  params = {
    minSize = 1000;
    maxSize = 10000;
  };
  
  builder = ''
    # Access params via $CAST_TRANSFORM_PARAMS
    MIN=$(echo "$CAST_TRANSFORM_PARAMS" | jq -r '.minSize')
    MAX=$(echo "$CAST_TRANSFORM_PARAMS" | jq -r '.maxSize')
    
    for file in "$SOURCE_DATA"/*; do
      SIZE=$(stat -c%s "$file")
      if [ $SIZE -ge $MIN ] && [ $SIZE -le $MAX ]; then
        cp "$file" "$CAST_OUTPUT/"
      fi
    done
  '';
}
```

### External Builder Scripts

```nix
cast.lib.transform {
  name = "complex-transform";
  src = myDataset;
  builder = ./scripts/transform.sh;  # External script file
}
```

The builder can also be a package:

```nix
builder = pkgs.writeShellScript "transform" ''
  #!/usr/bin/env bash
  # Complex transformation logic
'';
```
