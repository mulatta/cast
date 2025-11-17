# Transform dataset
# This will be fully implemented in task 9
{
  lib,
  pkgs,
  ...
}: {
  name,
  src,
  builder,
  outputs ? ["out"],
}:
# Stub implementation - returns a placeholder derivation
pkgs.stdenv.mkDerivation {
  pname = "cast-transform-${name}";
  version = "stub";

  inherit src builder outputs;

  phases = ["installPhase"];

  installPhase = ''
    mkdir -p $out
    echo "Stub: Transform ${name}" > $out/README
    echo "This is a placeholder. Full implementation in task 9." >> $out/README
  '';

  passthru = {
    transformationType = name;
  };
}
