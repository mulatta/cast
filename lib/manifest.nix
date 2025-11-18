# Manifest utilities
# Utility functions for working with CAST manifests
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
  # dataPath should be the path to the dataset's data directory
  manifestToEnv = manifest: dataPath: let
    datasetName = lib.toUpper (lib.replaceStrings ["-"] ["_"] manifest.dataset.name);
  in {
    "CAST_DATASET_${datasetName}" = dataPath;
    "CAST_DATASET_${datasetName}_VERSION" = manifest.dataset.version;
    "CAST_DATASET_${datasetName}_NAME" = manifest.dataset.name;
  };

  # Validate manifest structure
  # Returns true if manifest has required fields
  validateManifest = manifest:
    manifest ? schema_version
    && manifest ? dataset
    && manifest.dataset ? name
    && manifest.dataset ? version
    && manifest ? source
    && manifest ? contents
    && builtins.isList manifest.contents;

  # Get all file hashes from manifest
  getFileHashes = manifest:
    map (content: content.hash) manifest.contents;

  # Get total size of all files in manifest
  getTotalSize = manifest:
    builtins.foldl' (acc: content: acc + content.size) 0 manifest.contents;

  # Filter manifest contents by path pattern
  # Returns new manifest with filtered contents
  filterByPath = manifest: pattern: let
    filtered = builtins.filter (content:
      lib.hasInfix pattern content.path)
    manifest.contents;
  in
    manifest
    // {
      contents = filtered;
      dataset = manifest.dataset // {description = "${manifest.dataset.description} (filtered by: ${pattern})";};
    };

  # Get transformation chain as a list
  getTransformationChain = manifest:
    manifest.transformations or [];

  # Get source hash (original archive hash before any transformations)
  getSourceHash = manifest:
    if manifest ? source && manifest.source ? archive_hash
    then manifest.source.archive_hash
    else "blake3:unknown";
}
