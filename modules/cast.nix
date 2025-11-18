# NixOS module for CAST (Content-Addressed Storage Tool)
#
# This module provides system-wide database management using CAST.
# It allows administrators to define databases that are available to all users.
#
# Example usage in configuration.nix:
#
#   services.cast = {
#     enable = true;
#     storePath = "/var/lib/cast";
#     databases = {
#       ncbi-nr = {
#         name = "ncbi-nr";
#         version = "2024-01-15";
#         manifest = ./manifests/ncbi-nr.json;
#       };
#       uniprot = {
#         name = "uniprot";
#         version = "2024-01";
#         manifest = ./manifests/uniprot.json;
#       };
#     };
#   };
#
# Users can then access databases via environment variables:
#   $CAST_DATASET_NCBI_NR
#   $CAST_DATASET_UNIPROT
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.cast;

  # Import CAST library from the flake
  # Note: This assumes the module is used from the CAST flake
  # For external use, users should pass the CAST flake as an input
  castLib = import ../lib {
    inherit lib pkgs;
  };

  # Create configured CAST library with system storePath
  configuredCastLib = castLib.configure {
    inherit (cfg) storePath;
  };

  # Build dataset derivations from user-defined databases
  datasetDerivations = mapAttrs (_name: dbConfig:
    configuredCastLib.mkDataset dbConfig)
  cfg.databases;

  # Create a package that provides all databases
  allDatabasesPackage = pkgs.buildEnv {
    name = "cast-system-databases";
    paths = attrValues datasetDerivations;
    pathsToLink = ["/"];
  };
in {
  # ═══════════════════════════════════════════════════════════════
  # Module Options
  # ═══════════════════════════════════════════════════════════════

  options.services.cast = {
    enable = mkEnableOption "CAST content-addressed storage system";

    storePath = mkOption {
      type = types.str;
      default = "/var/lib/cast";
      example = "/data/scientific-databases";
      description = ''
        Directory where CAST will store database files.

        This directory will be created automatically with appropriate permissions.
        All databases defined in `services.cast.databases` will use this storage location.
      '';
    };

    databases = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Database name (used for environment variables)";
            example = "ncbi-nr";
          };

          version = mkOption {
            type = types.str;
            description = "Database version identifier";
            example = "2024-01-15";
          };

          manifest = mkOption {
            type = types.either types.path types.attrs;
            description = ''
              Path to manifest JSON file or inline manifest definition.

              Can be either a path to a JSON file or an attribute set defining the manifest.
            '';
            example = literalExpression "./manifests/ncbi-nr.json";
          };

          storePath = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Override the global storePath for this specific database.

              If null, uses the global services.cast.storePath.
            '';
          };
        };
      });
      default = {};
      example = literalExpression ''
        {
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
        }
      '';
      description = ''
        System-wide databases to be managed by CAST.

        Each database will be built and made available system-wide.
        Users can access databases via environment variables like:
        `CAST_DATASET_<NAME>` (where name is uppercased).
      '';
    };

    installCLI = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to install the CAST CLI tool (`cast`) in system packages.

        When enabled, the `cast` command will be available to all users.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "cast";
      description = "User account under which CAST storage directory is owned";
    };

    group = mkOption {
      type = types.str;
      default = "cast";
      description = "Group under which CAST storage directory is owned";
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # Module Implementation
  # ═══════════════════════════════════════════════════════════════

  config = mkIf cfg.enable {
    # Create CAST user and group
    users.users.${cfg.user} = mkIf (cfg.user == "cast") {
      description = "CAST storage system user";
      inherit (cfg) group;
      isSystemUser = true;
    };

    users.groups.${cfg.group} = mkIf (cfg.group == "cast") {};

    # Install CAST CLI tool if requested
    # Note: cast-cli should be provided via overlay or flake packages
    environment.systemPackages =
      (optional (cfg.installCLI && (pkgs ? cast-cli)) pkgs.cast-cli)
      ++ optional (cfg.databases != {}) allDatabasesPackage;

    # Create storage directory with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.storePath} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.storePath}/store 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Set environment variables for all databases
    # This makes databases available to all users and services
    environment.variables = let
      # Generate environment variables for each database
      databaseEnvVars = mapAttrs' (name: drv: let
        envName = toUpper (replaceStrings ["-"] ["_"] name);
      in
        nameValuePair "CAST_DATASET_${envName}" "${drv}/data")
      datasetDerivations;
    in
      databaseEnvVars;

    # Provide databases as flake output for other modules
    # This allows other NixOS modules to access CAST databases
    # Example: systemd.services.myservice.path = [ config.services.cast.databases.ncbi-nr ];
    services.cast.databases = datasetDerivations;

    # Assertions and warnings
    assertions = [
      {
        assertion = cfg.storePath != "";
        message = "services.cast.storePath must not be empty";
      }
      {
        assertion = hasPrefix "/" cfg.storePath;
        message = "services.cast.storePath must be an absolute path";
      }
    ];

    warnings =
      optional (cfg.databases == {})
      "services.cast.databases is empty - no databases will be available"
      ++ optional (!cfg.installCLI)
      "services.cast.installCLI is disabled - 'cast' command will not be available";
  };

  # ═══════════════════════════════════════════════════════════════
  # Module Metadata
  # ═══════════════════════════════════════════════════════════════

  meta = {
    maintainers = []; # Add maintainers here
    doc = ./cast.md; # Optional: separate documentation file
  };
}
