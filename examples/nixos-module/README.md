# CAST NixOS Module Example

This example demonstrates how to use the CAST NixOS module for system-wide database management.

## Overview

The CAST NixOS module allows you to:
- Define databases once in `configuration.nix`
- Make databases available to all users system-wide
- Manage storage permissions and directory structure
- Optionally install the `cast` CLI tool

## Quick Start

### 1. Add CAST as a Flake Input

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    cast.url = "github:yourusername/cast";
  };

  outputs = { self, nixpkgs, cast }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        cast.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Configure CAST in configuration.nix

```nix
# configuration.nix
{ config, pkgs, ... }:
{
  services.cast = {
    enable = true;
    storePath = "/var/lib/cast-databases";

    databases = {
      ncbi-nr = {
        name = "ncbi-nr";
        version = "2024-01-15";
        manifest = ./manifests/ncbi-nr.json;
      };

      uniprot = {
        name = "uniprot";
        version = "2024-01";
        manifest = ./manifests/uniprot.json;
      };
    };
  };
}
```

### 3. Access Databases

After rebuilding your system, databases are available via environment variables:

```bash
# Environment variables are set automatically
echo $CAST_DATASET_NCBI_NR
# Output: /nix/store/xxx-cast-dataset-ncbi-nr-2024-01-15/data

echo $CAST_DATASET_UNIPROT
# Output: /nix/store/xxx-cast-dataset-uniprot-2024-01/data

# Use in scripts
mmseqs search \
  query.fasta \
  "$CAST_DATASET_NCBI_NR/nr.fasta" \
  results.tsv
```

## Module Options

### `services.cast.enable`

**Type**: `boolean`
**Default**: `false`

Enable the CAST database management system.

### `services.cast.storePath`

**Type**: `string`
**Default**: `"/var/lib/cast"`

Directory where CAST stores database files. This directory is created automatically with appropriate permissions.

### `services.cast.databases`

**Type**: `attrsOf (submodule)`
**Default**: `{}`

Attribute set of databases to manage. Each database has the following options:

- **`name`** (string, required): Database name
- **`version`** (string, required): Version identifier
- **`manifest`** (path or attrs, required): Manifest file or inline definition
- **`storePath`** (string, optional): Override global storePath for this database

**Example**:
```nix
databases = {
  ncbi-nr = {
    name = "ncbi-nr";
    version = "2024-01-15";
    manifest = ./manifests/ncbi-nr.json;
  };

  # Inline manifest
  test-db = {
    name = "test-db";
    version = "1.0.0";
    manifest = {
      schema_version = "1.0";
      dataset = {
        name = "test-db";
        version = "1.0.0";
        description = "Test database";
      };
      source = {
        url = "https://example.com/test.tar.gz";
        archive_hash = "blake3:...";
      };
      contents = [];
      transformations = [];
    };
  };
};
```

### `services.cast.installCLI`

**Type**: `boolean`
**Default**: `true`

Install the CAST CLI tool (`cast`) in system packages.

### `services.cast.user`

**Type**: `string`
**Default**: `"cast"`

User account under which CAST storage directory is owned.

### `services.cast.group`

**Type**: `string`
**Default**: `"cast"`

Group under which CAST storage directory is owned.

## Use Cases

### 1. Lab-Wide Database Server

```nix
# Centralized database server for a research lab
services.cast = {
  enable = true;
  storePath = "/data/shared-databases";

  databases = {
    # Sequence databases
    ncbi-nr = { name = "ncbi-nr"; version = "2024-01-15"; manifest = ./ncbi-nr.json; };
    ncbi-nt = { name = "ncbi-nt"; version = "2024-01-15"; manifest = ./ncbi-nt.json; };
    uniprot = { name = "uniprot"; version = "2024-01"; manifest = ./uniprot.json; };

    # Protein structure databases
    pdb = { name = "pdb"; version = "2024-01-10"; manifest = ./pdb.json; };
    alphafold = { name = "alphafold"; version = "v4"; manifest = ./alphafold.json; };

    # Domain databases
    pfam = { name = "pfam"; version = "35.0"; manifest = ./pfam.json; };
    interpro = { name = "interpro"; version = "95.0"; manifest = ./interpro.json; };
  };

  # Allow lab members to access databases
  user = "databases";
  group = "lab";
};

# Create lab group
users.groups.lab = {};

# Add lab members
users.users.alice.extraGroups = [ "lab" ];
users.users.bob.extraGroups = [ "lab" ];
```

### 2. Multi-Version Database Management

```nix
# Keep multiple versions of the same database
services.cast.databases = {
  ncbi-nr-latest = {
    name = "ncbi-nr-latest";
    version = "2024-02-01";
    manifest = ./manifests/ncbi-nr-2024-02-01.json;
  };

  ncbi-nr-stable = {
    name = "ncbi-nr-stable";
    version = "2024-01-15";
    manifest = ./manifests/ncbi-nr-2024-01-15.json;
  };

  ncbi-nr-archive = {
    name = "ncbi-nr-archive";
    version = "2023-12-01";
    manifest = ./manifests/ncbi-nr-2023-12-01.json;
    storePath = "/mnt/archive/databases";  # Use different storage
  };
};
```

### 3. Per-Project Storage

```nix
# Separate storage for different projects
services.cast.databases = {
  project-a-db = {
    name = "project-a-ncbi";
    version = "2024-01-15";
    manifest = ./project-a/ncbi.json;
    storePath = "/data/project-a/databases";
  };

  project-b-db = {
    name = "project-b-ncbi";
    version = "2024-01-15";
    manifest = ./project-b/ncbi.json;
    storePath = "/data/project-b/databases";
  };
};
```

## Integration with Other Services

### systemd Services

```nix
systemd.services.analysis-pipeline = {
  description = "Automated analysis pipeline";

  # Database will be available via environment variables
  path = [ config.services.cast.databases.ncbi-nr ];

  script = ''
    mmseqs search \
      /data/queries/*.fasta \
      "$CAST_DATASET_NCBI_NR/nr.fasta" \
      /data/results/
  '';

  serviceConfig = {
    User = "pipeline";
    Group = "cast";
  };
};
```

### User Services

```nix
# Allow user services to access databases
systemd.user.services.my-analysis = {
  description = "Personal analysis";

  script = ''
    export PATH="${config.services.cast.databases.ncbi-nr}/bin:$PATH"
    # Run analysis using $CAST_DATASET_NCBI_NR
  '';
};
```

## Troubleshooting

### Databases Not Available

**Problem**: Environment variables not set

**Solution**: Ensure you've rebuilt the system:
```bash
sudo nixos-rebuild switch
```

Log out and log back in to refresh environment variables.

### Permission Denied

**Problem**: Cannot access storage directory

**Solution**: Add your user to the CAST group:
```nix
users.users.myuser.extraGroups = [ "cast" ];
```

### Module Not Found

**Problem**: `services.cast` not recognized

**Solution**: Ensure CAST module is imported:
```nix
imports = [ inputs.cast.nixosModules.default ];
```

## Testing

Test the module in a VM:

```bash
# Build VM
nixos-rebuild build-vm -I nixos-config=./configuration.nix

# Run VM
./result/bin/run-nixos-vm

# Inside VM, check databases
echo $CAST_DATASET_TEST_DB
ls -la /var/lib/cast-databases/
```

## See Also

- [CAST README](../../README.md) - General CAST documentation
- [CONFIGURATION.md](../../CONFIGURATION.md) - Configuration guide
- [Database Registry Example](../database-registry/) - Flake-based database management
