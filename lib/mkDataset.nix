# Create a dataset derivation from manifest
# Creates a symlink farm pointing to files in CAS storage
{
  lib,
  pkgs,
  ...
}: {
  name,
  version,
  manifest,
  storePath ? null,
}: let
  # Import manifest utilities
  manifestUtils = import ./manifest.nix {inherit lib;};

  # Parse manifest if it's a path, otherwise use as-is
  manifestData =
    if builtins.isPath manifest || builtins.isString manifest
    then manifestUtils.readManifest manifest
    else manifest;

  # Determine CAST store path
  # Priority: 1) storePath parameter, 2) CAST_STORE env var, 3) default
  castStore =
    if storePath != null
    then storePath
    else builtins.getEnv "CAST_STORE";

  # Default to ~/.cache/cast if no store path specified
  effectiveStorePath =
    if castStore != ""
    then castStore
    else builtins.getEnv "HOME" + "/.cache/cast";

  # Generate dataset environment variable name
  datasetEnvName = lib.toUpper (lib.replaceStrings ["-"] ["_"] name);
in
  pkgs.stdenv.mkDerivation {
    pname = "cast-dataset-${name}";
    inherit version;

    # No source needed - we're creating symlinks
    dontUnpack = true;
    dontBuild = true;

    # Pass manifest data to build phase
    manifestJson = builtins.toJSON manifestData;

    installPhase = ''
      mkdir -p $out/data

      # Parse manifest and create symlinks
      ${pkgs.jq}/bin/jq -r '.contents[] | "\(.path)\t\(.hash)"' <<< "$manifestJson" | while IFS=$'\t' read -r path hash; do
        # Create directory structure
        dir=$(dirname "$path")
        if [ "$dir" != "." ]; then
          mkdir -p "$out/data/$dir"
        fi

        # Convert hash to CAS path
        stripped=$(echo "$hash" | sed 's/^blake3://')
        prefix2=$(echo "$stripped" | cut -c1-2)
        prefix4=$(echo "$stripped" | cut -c3-4)
        cas_path="${effectiveStorePath}/store/$prefix2/$prefix4/$stripped"

        # Create symlink (will be dangling if CAS doesn't have the file yet)
        ln -s "$cas_path" "$out/data/$path"
      done

      # Copy manifest to output
      echo "$manifestJson" | ${pkgs.jq}/bin/jq '.' > $out/manifest.json

      # Create metadata file
      cat > $out/dataset-info.json <<EOF
      {
        "name": "${name}",
        "version": "${version}",
        "castStore": "${effectiveStorePath}",
        "dataPath": "$out/data"
      }
      EOF
    '';

    # Setup hook for automatic environment variable export
    # When this dataset is added to buildInputs, the environment variables are automatically set
    setupHook = pkgs.writeText "setup-hook.sh" ''
      castDatasetHook() {
        export CAST_DATASET_${datasetEnvName}="$1/data"
        export CAST_DATASET_${datasetEnvName}_VERSION="${version}"
        export CAST_DATASET_${datasetEnvName}_MANIFEST="$1/manifest.json"
      }

      addEnvHooks "$hostOffset" castDatasetHook
    '';

    passthru = {
      inherit manifest manifestData storePath;
      castDatasetName = datasetEnvName;
      castStorePath = effectiveStorePath;

      # Environment variables for shell integration
      shellVars = {
        "CAST_DATASET_${datasetEnvName}" = "$out/data";
        "CAST_DATASET_${datasetEnvName}_VERSION" = version;
        "CAST_DATASET_${datasetEnvName}_MANIFEST" = "$out/manifest.json";
      };
    };

    meta = with lib; {
      description = manifestData.dataset.description or "CAST dataset: ${name}";
      # Default to free license - data is typically not subject to software licenses
      license = licenses.free;
      platforms = platforms.all;
    };
  }
