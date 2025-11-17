# Nix type definitions for CAST
# This will be expanded in task 3.6
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
}
