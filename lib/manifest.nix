# Manifest utilities
# This will be fully implemented in task 3.5
{lib, ...}: rec {
  # Read a manifest file and parse JSON
  readManifest = path:
    if builtins.pathExists path
    then builtins.fromJSON (builtins.readFile path)
    else throw "Manifest file not found: ${toString path}";

  # Convert a BLAKE3 hash to CAS storage path
  # Format: $CAST_STORE/store/{hash[:2]}/{hash[2:4]}/{full_hash}
  hashToPath = storePath: hash: let
    # Remove "blake3:" prefix if present
    stripped = lib.removePrefix "blake3:" hash;
  in "${storePath}/store/${builtins.substring 0 2 stripped}/${builtins.substring 2 2 stripped}/${stripped}";

  # Convert manifest to environment variables
  # Creates CAST_DATASET_<NAME> variables
  manifestToEnv = manifest: let
    datasetName = lib.toUpper (lib.replaceStrings ["-"] ["_"] manifest.dataset.name);
  in {
    "CAST_DATASET_${datasetName}" = "stub-path";
    "CAST_DATASET_${datasetName}_VERSION" = manifest.dataset.version;
  };
}
