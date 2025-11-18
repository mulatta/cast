# Nix type definitions for CAST
{lib, ...}:
with lib.types; rec {
  # Manifest schema type
  manifestType = submodule {
    options = {
      schema_version = lib.mkOption {
        type = str;
        default = "1.0";
        description = "Manifest schema version";
      };

      dataset = lib.mkOption {
        type = datasetType;
        description = "Dataset metadata";
      };

      source = lib.mkOption {
        type = sourceType;
        description = "Source information";
      };

      contents = lib.mkOption {
        type = listOf contentType;
        default = [];
        description = "List of content files";
      };

      transformations = lib.mkOption {
        type = listOf transformationType;
        default = [];
        description = "Transformation provenance chain";
      };
    };
  };

  # Dataset metadata type
  datasetType = submodule {
    options = {
      name = lib.mkOption {
        type = str;
        description = "Dataset name";
      };

      version = lib.mkOption {
        type = str;
        description = "Dataset version";
      };

      description = lib.mkOption {
        type = nullOr str;
        default = null;
        description = "Dataset description";
      };
    };
  };

  # Source information type
  sourceType = submodule {
    options = {
      url = lib.mkOption {
        type = nullOr str;
        default = null;
        description = "Source URL";
      };

      download_date = lib.mkOption {
        type = nullOr str;
        default = null;
        description = "Download timestamp (ISO 8601)";
      };

      server_mtime = lib.mkOption {
        type = nullOr str;
        default = null;
        description = "Server modification time (ISO 8601)";
      };

      archive_hash = lib.mkOption {
        type = nullOr str;
        default = null;
        description = "BLAKE3 hash of archive";
      };
    };
  };

  # Content file type
  contentType = submodule {
    options = {
      path = lib.mkOption {
        type = str;
        description = "File path relative to dataset root";
      };

      hash = lib.mkOption {
        type = str;
        description = "BLAKE3 hash of file content";
      };

      size = lib.mkOption {
        type = int;
        description = "File size in bytes";
      };

      executable = lib.mkOption {
        type = bool;
        default = false;
        description = "Whether file is executable";
      };
    };
  };

  # Transformation type
  transformationType = submodule {
    options = {
      type = lib.mkOption {
        type = str;
        description = "Transformation type identifier";
      };

      from = lib.mkOption {
        type = str;
        description = "Input hash";
      };

      params = lib.mkOption {
        type = nullOr attrs;
        default = null;
        description = "Transformation parameters";
      };
    };
  };

  # Function parameter types
  mkDatasetArgs = submodule {
    options = {
      name = lib.mkOption {
        type = str;
        description = "Dataset name";
      };

      version = lib.mkOption {
        type = str;
        description = "Dataset version";
      };

      manifest = lib.mkOption {
        type = either path attrs;
        description = "Path to manifest.json or manifest attrset";
      };

      storePath = lib.mkOption {
        type = nullOr path;
        default = null;
        description = "Optional CAST store path override";
      };
    };
  };

  fetchDatabaseArgs = submodule {
    options = {
      name = lib.mkOption {
        type = str;
        description = "Database name";
      };

      url = lib.mkOption {
        type = str;
        description = "Download URL";
      };

      hash = lib.mkOption {
        type = nullOr str;
        default = null;
        description = "Expected BLAKE3 hash";
      };

      extract = lib.mkOption {
        type = bool;
        default = false;
        description = "Whether to extract archive";
      };

      metadata = lib.mkOption {
        type = attrs;
        default = {};
        description = "Additional metadata";
      };
    };
  };

  transformArgs = submodule {
    options = {
      name = lib.mkOption {
        type = str;
        description = "Transformation name";
      };

      src = lib.mkOption {
        type = package;
        description = "Source dataset derivation";
      };

      builder = lib.mkOption {
        type = either path str;
        description = "Builder script path or inline shell code";
      };

      params = lib.mkOption {
        type = attrs;
        default = {};
        description = "Transformation parameters";
      };
    };
  };

  symlinkSubsetArgs = submodule {
    options = {
      name = lib.mkOption {
        type = str;
        description = "Subset name";
      };

      paths = lib.mkOption {
        type = listOf (either attrs (either path str));
        description = "List of datasets, name/path pairs, or plain paths";
      };

      version = lib.mkOption {
        type = str;
        default = "1.0";
        description = "Version identifier";
      };
    };
  };

  # Validators
  validators = {
    # Validate BLAKE3 hash format
    isValidBlake3Hash = hash:
      builtins.isString hash
      && (
        builtins.match "blake3:[a-f0-9]{64}" hash
        != null
        || builtins.match "[a-f0-9]{64}" hash != null
      );

    # Validate manifest structure
    isValidManifest = manifest:
      manifest ? schema_version
      && manifest ? dataset
      && manifest.dataset ? name
      && manifest.dataset ? version
      && manifest ? source
      && manifest ? contents
      && builtins.isList manifest.contents;

    # Validate ISO 8601 date format (basic check)
    isValidISODate = date:
      builtins.isString date
      && builtins.match "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" date != null;
  };
}
