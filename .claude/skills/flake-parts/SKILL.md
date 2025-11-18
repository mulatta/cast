---
name: flake-parts
description: Comprehensive guide for building Nix flakes using the flake-parts framework, including module system patterns, perSystem configuration, and best practices
version: 1.0.0
author: Assistant
tags: [nix, flakes, flake-parts, nixos, development]
---

# flake-parts Skill

## Overview

flake-parts is a module system framework for Nix flakes that provides:

- Modular organization of flake configuration
- Elegant handling of the `system` parameter via `perSystem`
- Reusable modules that can be shared across projects
- Standard interfaces for common flake outputs

This skill helps you effectively use flake-parts in your Nix projects.

## When to Use This Skill

Use this skill when:

- Creating a new Nix flake with flake-parts
- Organizing complex flake configurations into modules
- Working with `perSystem` definitions
- Defining packages, apps, devShells, or other per-system outputs
- Creating reusable flake modules
- Troubleshooting flake-parts module issues

## Core Concepts

### Basic Structure

A flake-parts flake has this structure:

```nix
{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [
        # Import additional modules here
      ];
      perSystem = { config, pkgs, system, ... }: {
        # Per-system configuration
      };
      flake = {
        # System-agnostic outputs
      };
    };
}
```

### Module Arguments

**Top-level module arguments:**

- `inputs` - All flake inputs
- `self` - The flake itself
- `lib` - Nixpkgs lib
- `config` - The top-level configuration
- `options` - The top-level options
- `withSystem` - Function to access per-system config
- `moduleWithSystem` - Helper for system-aware modules

**perSystem module arguments:**

- `system` - Current system string (e.g., "x86_64-linux")
- `pkgs` - Nixpkgs for current system (from inputs'.nixpkgs.legacyPackages)
- `config` - Current perSystem configuration
- `self'` - System-specific outputs from self
- `inputs'` - System-specific outputs from all inputs
- `final` - (with easyOverlay) Final package set

### Transposition System

flake-parts "transposes" between two structures:

```
perSystem:  .${system}.${attribute}
outputs:    .${attribute}.${system}
```

Standard transposed attributes:

- `packages` - Built with `nix build .#name`
- `apps` - Run with `nix run .#name`
- `checks` - Validated with `nix flake check`
- `devShells` - Entered with `nix develop .#name`
- `formatter` - Used by `nix fmt`
- `legacyPackages` - For large package sets

## Common Patterns

### 1. Basic Package Definition

```nix
perSystem = { pkgs, ... }: {
  packages.default = pkgs.hello;

  packages.my-tool = pkgs.callPackage ./my-tool { };
}
```

### 2. Development Shells

```nix
perSystem = { pkgs, config, ... }: {
  devShells.default = pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      cargo
      rustc
    ];
    inputsFrom = [ config.packages.default ];
  };
}
```

### 3. Apps

```nix
perSystem = { config, ... }: {
  apps.default = {
    type = "app";
    program = "${config.packages.my-tool}/bin/my-tool";
  };
}
```

### 4. Multi-Module Organization

**flake.nix:**

```nix
{
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./nix/packages.nix
        ./nix/dev-shells.nix
      ];
      systems = [ "x86_64-linux" "aarch64-darwin" ];
    };
}
```

**nix/packages.nix:**

```nix
{ self, ... }: {
  perSystem = { pkgs, ... }: {
    packages.tool1 = pkgs.callPackage ./tool1.nix { };
    packages.tool2 = pkgs.callPackage ./tool2.nix { };
  };
}
```

### 5. Using inputs' and self'

```nix
perSystem = { inputs', self', pkgs, ... }: {
  # Access nixpkgs packages for current system
  packages.curl = inputs'.nixpkgs.legacyPackages.curl;

  # Reference own packages
  packages.wrapper = pkgs.writeShellScript "wrapper" ''
    ${self'.packages.tool1}/bin/tool1 "$@"
  '';
}
```

### 6. System-Agnostic Outputs

```nix
{
  flake = {
    nixosModules.my-module = { pkgs, ... }: {
      services.my-service.enable = true;
    };

    overlays.default = final: prev: {
      my-package = final.callPackage ./package.nix { };
    };
  };
}
```

### 7. Accessing perSystem from Top-Level

```nix
{ withSystem, ... }: {
  flake.nixosConfigurations.my-machine = withSystem "x86_64-linux"
    ({ config, inputs', ... }:
      inputs'.nixpkgs.lib.nixosSystem {
        modules = [
          {
            environment.systemPackages = [
              config.packages.my-tool
            ];
          }
        ];
      }
    );
}
```

## Built-in Modules

### Standard Transposed Modules

- `modules/apps.nix` - Application definitions
- `modules/packages.nix` - Package definitions
- `modules/checks.nix` - Tests and checks
- `modules/devShells.nix` - Development environments
- `modules/formatter.nix` - Code formatters

### Extra Modules (must import explicitly)

- `extras/easyOverlay.nix` - Easy overlay creation from perSystem
- `extras/flakeModules.nix` - Export modules for other flakes
- `extras/partitions.nix` - Lazy input loading
- `extras/bundlers.nix` - Package bundlers

Example import:

```nix
{
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        flake-parts.flakeModules.easyOverlay
      ];
      # ...
    };
}
```

## Advanced Patterns

### Unfree Packages

```nix
{ nixpkgs, ... }:
{
  perSystem = { system, ... }: {
    _module.args.pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    packages.unfree-pkg = pkgs.someUnfreePackage;
  };
}
```

### Partitions (Lazy Development Inputs)

```nix
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs.devShells = "dev";
  partitionedAttrs.checks = "dev";

  partitions.dev = {
    extraInputsFlake = ./dev;
    module = {
      imports = [ ./dev/flake-module.nix ];
    };
  };
}
```

### Creating Reusable Modules

```nix
# my-module.nix
{ lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.myFeature = lib.mkOption {
      type = lib.types.package;
      description = "My custom feature";
    };
  };
}
```

## Troubleshooting

### Error: "system: argument not found"

**Wrong:**

```nix
perSystem = system: { config, pkgs, ... }: { }
```

**Correct:**

```nix
perSystem = { config, pkgs, system, ... }: { }
```

### Error: self/inputs not available in perSystem

Use `self'` and `inputs'` instead of `self` and `inputs` in perSystem:

```nix
perSystem = { self', inputs', ... }: {
  packages.default = inputs'.nixpkgs.legacyPackages.hello;
}
```

### Infinite Recursion with inputs

**Wrong:**

```nix
outputs = inputs@{ flake-parts, self, ... }:
  flake-parts.lib.mkFlake { inherit self; } { }
```

**Correct:**

```nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } { }
```

### Missing nixpkgs Input

If you see "flake does not have a nixpkgs input", either:

1. Add nixpkgs to inputs, or
2. Set pkgs explicitly:

```nix
perSystem = { system, ... }: {
  _module.args.pkgs = import inputs.some-other-nixpkgs { inherit system; };
}
```

## Best Practices

1. **Use perSystem for per-system outputs** - Packages, apps, checks, devShells
2. **Use flake for system-agnostic outputs** - Modules, overlays, lib
3. **Split large configurations into separate module files**
4. **Use inputs' and self' instead of inputs and self in perSystem**
5. **Leverage existing modules from flake.parts ecosystem**
6. **Use mkPerSystemOption when defining new perSystem options**
7. **Consider partitions for development-only dependencies**

## Quick Reference

### Initialize New Project

```bash
nix flake init -t github:hercules-ci/flake-parts
```

### Common Commands

```bash
nix flake show              # View all outputs
nix build .#package-name    # Build a package
nix develop                 # Enter default devShell
nix run .#app-name          # Run an app
nix flake check             # Run all checks
```

### Module File Template

```nix
{ self, lib, config, ... }:
{
  options.perSystem = lib.mkOption {
    # Define perSystem options
  };

  config = {
    perSystem = { config, pkgs, system, ... }: {
      # Define perSystem config
    };

    flake = {
      # Define system-agnostic outputs
    };
  };
}
```

## Further Resources

- Official docs: https://flake.parts
- Module options reference: https://flake.parts/options/flake-parts.html
- GitHub: https://github.com/hercules-ci/flake-parts
- Examples: See examples/ directory in flake-parts repo
