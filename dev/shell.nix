{
  perSystem = {
    pkgs,
    inputs',
    ...
  }: {
    devShells.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        # Nix tools
        nixVersions.latest
        gitMinimal
        inputs'.nix-ai-tools.packages.claude-code
        nodejs

        # Rust toolchain and development tools
        (rust-bin.stable.latest.default.override {
          extensions = ["rust-src" "rust-analyzer"];
        })
        cargo-watch
        clippy
        rustfmt

        # CAST dependencies
        sqlite
        b3sum
      ];

      # Environment variables for CAST development
      CAST_STORE = "${toString ./.}/.cache/cast-store";
      CAST_LOG = "debug";
      RUST_BACKTRACE = "1";

      shellHook = ''
        echo "🎯 CAST Development Environment"
        echo "================================"
        echo "Rust version: $(rustc --version)"
        echo "Cargo version: $(cargo --version)"
        echo "CAST store: $CAST_STORE"
        echo ""
        echo "Available commands:"
        echo "  cargo build --manifest-path packages/cast-cli/Cargo.toml"
        echo "  cargo test --manifest-path packages/cast-cli/Cargo.toml"
        echo "  cargo watch -x check"
        echo "  nix flake check"
        echo "  nix fmt"
        echo ""
      '';
    };
  };
}
