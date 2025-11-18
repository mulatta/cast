# Simple Dataset Example

This example demonstrates how to create and use a basic CAST dataset with pre-existing data files.

## Files

- `manifest.json` - Dataset manifest with file metadata and BLAKE3 hashes
- `data/` - Sample data files
  - `sample.txt` - Simple text file
  - `users.csv` - CSV file with user data
- `flake.nix` - Nix flake that creates the dataset

## Usage

### Build the dataset

```bash
nix build .#example-dataset
```

This creates a derivation in `/nix/store` with:
- `manifest.json` - The dataset manifest
- `data/` - Symlinks to files in the CAST store

### Enter development shell

```bash
nix develop
```

The shell automatically:
- Sets `$CAST_DATASET_SIMPLE_EXAMPLE` to the dataset data directory
- Sets `$CAST_DATASET_SIMPLE_EXAMPLE_MANIFEST` to the manifest path
- Lists available files

### Access files in your project

Add this example as a flake input:

```nix
{
  inputs.simple-dataset.url = "path:./examples/simple-dataset";
  
  outputs = { self, nixpkgs, simple-dataset }: {
    packages.x86_64-linux.myApp = pkgs.mkDerivation {
      name = "my-app";
      buildInputs = [ simple-dataset.packages.x86_64-linux.example-dataset ];
      
      buildPhase = ''
        # Access dataset files
        cat "$CAST_DATASET_SIMPLE_EXAMPLE/sample.txt"
        cat "$CAST_DATASET_SIMPLE_EXAMPLE/users.csv"
      '';
    };
  };
}
```

## Setting up the CAST store

Before building, you need to store the actual files in the CAST store:

```bash
# Create CAST store directory (default location)
mkdir -p ~/.cache/cast/store

# Store the files using their BLAKE3 hashes
# For sample.txt (hash: 7a090e90...)
mkdir -p ~/.cache/cast/store/7a/09
cp data/sample.txt ~/.cache/cast/store/7a/09/7a090e90e50dfc028aa09c1ffbc85f108a5b3cc2a1a56289b5ab1a9301b59e88

# For users.csv (hash: 0fa9b6b6...)
mkdir -p ~/.cache/cast/store/0f/a9
cp data/users.csv ~/.cache/cast/store/0f/a9/0fa9b6b6c7c01285fb8b4d6e817c9ce14d78c26234d8716425e8bc5adc073f00
```

Alternatively, use the `cast-cli put` command (when implemented):

```bash
cast-cli put data/sample.txt
cast-cli put data/users.csv
```

## How it works

1. **Manifest** defines the dataset metadata and file inventory with BLAKE3 hashes
2. **mkDataset** creates a Nix derivation that:
   - Reads the manifest
   - Creates symlinks pointing to files in the CAST store (based on hashes)
   - Sets up environment variables for easy access
3. **CAST store** (`~/.cache/cast/store/`) contains the actual file content, organized by hash

This separation allows:
- **Reproducibility**: Same hash = same file
- **Deduplication**: Multiple datasets can reference the same file
- **Version control**: Manifests are small JSON files that can be tracked in git
