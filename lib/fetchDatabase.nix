# Download and register a database
# This will be fully implemented in task 3.3
{
  lib,
  pkgs,
  mkDataset,
  ...
}: {
  name,
  url,
  hash ? null,
  extract ? false,
  metadata ? {},
}:
# Stub implementation - returns a placeholder manifest
{
  schema_version = "1.0";
  dataset = {
    inherit name;
    version = "stub";
    description = "Stub: Database fetched from ${url}";
  };
  source = {
    inherit url;
    download_date = "stub";
    server_mtime = "stub";
    archive_hash = "blake3:${"0" * 64}";
  };
  contents = [];
  transformations = [];
}
