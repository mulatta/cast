# Database Registry Example

This example demonstrates how to create and manage a registry of datasets with multiple versions using CAST.

## Use Case

Scientific databases are frequently updated with new releases. This pattern allows you to:
- Maintain multiple versions of the same database
- Pin specific versions in your projects for reproducibility
- Test migrations between versions
- Share database versions across projects

## Structure

```
registry/
├── flake.nix              # Registry definition
└── manifests/             # Version manifests
    ├── test-db-1.0.0.json
    ├── test-db-1.1.0.json
    ├── test-db-2.0.0.json
    ├── uniprot-2024-01.json
    └── uniprot-2024-02.json
```

## Registry Organization

The flake exports databases in a hierarchical structure:

```nix
databases = {
  test-db = {
    "1.0.0" = <dataset>;
    "1.1.0" = <dataset>;
    "2.0.0" = <dataset>;
  };
  uniprot = {
    "2024-01" = <dataset>;
    "2024-02" = <dataset>;
  };
};
```

## Usage Patterns

### 1. Use in Another Project

Add the registry as a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    db-registry.url = "path:./examples/registry";
  };
  
  outputs = { self, nixpkgs, db-registry }: {
    packages.x86_64-linux.myApp = pkgs.mkDerivation {
      name = "my-app";
      buildInputs = [
        # Pin to specific version for reproducibility
        db-registry.databases.test-db."1.1.0"
      ];
      
      buildPhase = ''
        # Use the database
        echo "DB path: $CAST_DATASET_TEST_DB"
      '';
    };
  };
}
```

### 2. Development Shells

Different shells for different scenarios:

```bash
# Default shell (latest version)
nix develop

# Legacy shell (v1.1.0)
nix develop .#legacy

# Migration testing shell (multiple versions)
nix develop .#migration
```

### 3. Build Specific Versions

```bash
# Build latest
nix build .#test-db-latest

# Build stable version
nix build .#test-db-stable

# Build specific version directly
nix build .#databases.test-db.\"1.0.0\"
```

## Real-World Example

For actual biological databases:

```nix
{
  description = "Bioinformatics Database Registry";
  
  outputs = { self, nixpkgs, cast }: {
    databases = {
      # NCBI NR database
      ncbi-nr = {
        "2024-01-15" = cast.lib.mkDataset {
          name = "ncbi-nr";
          version = "2024-01-15";
          manifest = ./manifests/ncbi-nr-2024-01-15.json;
        };
        "2024-02-01" = cast.lib.mkDataset {
          name = "ncbi-nr";
          version = "2024-02-01";
          manifest = ./manifests/ncbi-nr-2024-02-01.json;
        };
      };
      
      # UniProt SwissProt
      uniprot-sprot = {
        "2024.01" = cast.lib.mkDataset {
          name = "uniprot-sprot";
          version = "2024.01";
          manifest = ./manifests/uniprot-sprot-2024.01.json;
        };
      };
      
      # Pfam protein families
      pfam = {
        "35.0" = cast.lib.mkDataset {
          name = "pfam";
          version = "35.0";
          manifest = ./manifests/pfam-35.0.json;
        };
      };
    };
    
    # Convenience: latest versions
    packages.x86_64-linux = {
      ncbi-nr-latest = self.databases.ncbi-nr."2024-02-01";
      uniprot-latest = self.databases.uniprot-sprot."2024.01";
      pfam-latest = self.databases.pfam."35.0";
    };
  };
}
```

## Version Management Strategies

### Semantic Versioning

For databases with semantic versioning:

```nix
databases.mydb = {
  "1.0.0" = ...;  # Initial release
  "1.1.0" = ...;  # Backward-compatible updates
  "2.0.0" = ...;  # Breaking changes
};
```

### Date-Based Versioning

For regularly updated databases:

```nix
databases.ncbi-nr = {
  "2024-01-15" = ...;
  "2024-02-01" = ...;
  "2024-02-15" = ...;
};
```

### Named Releases

For databases with named releases:

```nix
databases.genome = {
  "hg38" = ...;  # Human genome build 38
  "hg19" = ...;  # Human genome build 19
  "t2t" = ...;   # Telomere-to-telomere
};
```

## Migration Testing

Test migrations between versions:

```nix
devShells.migration-test = pkgs.mkShell {
  buildInputs = [
    databases.mydb."1.1.0"  # Old version
    databases.mydb."2.0.0"  # New version
  ];
  
  shellHook = ''
    # Run migration script
    ./scripts/test-migration.sh \
      "$CAST_DATASET_MYDB_V110" \
      "$CAST_DATASET_MYDB_V200"
  '';
};
```

## Automatic Updates

Create a script to fetch and add new versions:

```bash
#!/usr/bin/env bash
# update-databases.sh

# Download new UniProt release
VERSION=$(date +%Y-%m)
URL="ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/..."

# Create manifest
cast-cli fetch "$URL" --name "uniprot" --version "$VERSION" \
  > "manifests/uniprot-$VERSION.json"

# Update flake.nix to include new version
# (manual or scripted)
```

## Benefits

### Reproducibility
- Pin exact database versions in your projects
- Rebuild old analyses with same data

### Collaboration
- Share database registry across team
- Everyone uses same versions

### Testing
- Test with multiple versions simultaneously
- Verify backward compatibility

### Storage Efficiency
- CAST deduplicates common files across versions
- Only differences consume additional space

## Advanced: Transformed Versions

Maintain both raw and processed versions:

```nix
databases = {
  ncbi-nr-raw = {
    "2024-01" = cast.lib.mkDataset {...};
  };
  
  ncbi-nr-mmseqs = {
    "2024-01" = cast.lib.transform {
      name = "ncbi-nr-mmseqs";
      src = self.databases.ncbi-nr-raw."2024-01";
      builder = /* transform to MMseqs format */;
    };
  };
  
  ncbi-nr-blast = {
    "2024-01" = cast.lib.transform {
      name = "ncbi-nr-blast";
      src = self.databases.ncbi-nr-raw."2024-01";
      builder = /* transform to BLAST format */;
    };
  };
};
```

## Publishing

Share your registry by:

1. **Git repository:**
   ```bash
   git init
   git add flake.nix manifests/
   git commit -m "Add database registry"
   git remote add origin git@github.com:lab/databases.git
   git push
   ```

2. **Use in other projects:**
   ```nix
   inputs.databases.url = "github:lab/databases";
   ```

3. **Update with new versions:**
   ```bash
   cd databases-repo
   # Add new manifests
   git add manifests/new-version.json
   # Update flake.nix
   git commit -m "Add version X.Y.Z"
   git push
   ```

## Best Practices

1. **Naming:** Use consistent version naming across all databases
2. **Documentation:** Include release notes in manifest descriptions
3. **Testing:** Verify each version builds before committing
4. **Pruning:** Archive very old versions to separate flakes
5. **Metadata:** Include download dates and source URLs in manifests

## Example: Using in a Lab

```nix
# lab-databases/flake.nix
{
  description = "Lab bioinformatics database registry";
  
  outputs = { self, nixpkgs, cast }: {
    databases = {
      # Databases used by Lab Project A
      project-a = {
        ncbi-nr = self.databases.ncbi-nr."2024-01-15";
        uniprot = self.databases.uniprot."2024.01";
      };
      
      # Databases used by Lab Project B
      project-b = {
        ncbi-nr = self.databases.ncbi-nr."2024-02-01";  # Newer version
        pfam = self.databases.pfam."35.0";
      };
    };
  };
}
```

Researchers can then use:

```nix
inputs.lab-dbs.url = "git+ssh://lab-server/databases.git";

# Use project-specific database bundle
buildInputs = with lab-dbs.databases.project-a; [
  ncbi-nr
  uniprot
];
```
