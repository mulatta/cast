{
  perSystem = {
    pkgs,
    inputs',
    ...
  }: {
    devShells.default = pkgs.mkShellNoCC {
      buildInputs = with pkgs; [
        nixVersions.latest
        gitMinimal
        inputs'.nix-ai-tools.packages.claude-code
        nodejs
      ];
    };
  };
}
