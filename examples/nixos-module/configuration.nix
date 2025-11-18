# Example NixOS configuration using CAST module
#
# This demonstrates how to use the CAST NixOS module to manage
# system-wide scientific databases.
#
# Usage:
#   1. Import this module in your configuration.nix:
#      imports = [ ./path/to/cast/examples/nixos-module/configuration.nix ];
#
#   2. Or use directly in a test VM:
#      nixos-rebuild build-vm -I nixos-config=./configuration.nix
{pkgs, ...}: {
  # Import CAST flake's NixOS module
  # In a real configuration, you would import from inputs:
  # imports = [ inputs.cast.nixosModules.default ];

  # For this example, we'll define a minimal configuration
  # that demonstrates the CAST module options

  # Enable CAST system-wide database management
  services.cast = {
    enable = true;

    # Storage location for all databases
    storePath = "/var/lib/cast-databases";

    # Install cast-cli tool system-wide
    installCLI = true;

    # Define system-wide databases
    databases = {
      # Example: Test database
      test-db = {
        name = "test-db";
        version = "1.0.0";
        manifest = {
          schema_version = "1.0";
          dataset = {
            name = "test-db";
            version = "1.0.0";
            description = "Example test database for NixOS module demonstration";
          };
          source = {
            url = "generated://test-data";
            archive_hash = "blake3:0000000000000000000000000000000000000000000000000000000000000000";
          };
          contents = [];
          transformations = [];
        };
      };

      # Example: Another database with manifest file
      # ncbi-nr = {
      #   name = "ncbi-nr";
      #   version = "2024-01-15";
      #   manifest = ./manifests/ncbi-nr.json;
      # };
    };

    # User and group for storage ownership
    user = "cast";
    group = "cast";
  };

  # Additional system configuration for a complete NixOS system
  # (Only needed for testing with nixos-rebuild build-vm)

  boot.loader.grub.device = "/dev/sda";

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Minimal system configuration
  networking.hostName = "cast-demo";

  # Enable basic services
  services.openssh.enable = true;

  # Allow users in the "cast" group to access databases
  users.users.demo = {
    isNormalUser = true;
    extraGroups = ["wheel" "cast"];
    password = "demo";
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    htop
  ];

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
