---
name: nix-project-dev
description: Comprehensive guide for developing Nix-based projects using flakes, flake-parts, and modern Nix tooling. Covers project structure, iterative development workflow, testing strategies, and validation processes.
version: 1.0.0
author: Seungwon
tags: [nix, flakes, development, testing, validation]
---

# Nix Project Development Skill

This skill provides comprehensive guidelines for developing robust Nix-based projects using modern tooling and best practices. It emphasizes iterative development, proper validation, and strategic testing.

## Core Principles

1. **Iterative Validation**: Validate frequently at each development stage
2. **Strategic Testing**: Introduce tests only when abstractions are stable
3. **Declarative Structure**: Use flake-parts for modular, maintainable flakes
4. **Fast Feedback**: Leverage tools like nix-fast-build for quick iteration

## Project Structure

### For Non-Nix Projects (Nix as Development Environment)

```
project-root/
├── flake.nix
├── flake.lock
├── nix/
│   ├── formatter.nix
│   ├── shell.nix
│   ├── packages/
│   └── checks.nix
└── [project files...]
```

### For Nix Projects (Nix as Primary Technology)

```
project-root/
├── flake.nix
├── flake.lock
├── dev/
│   ├── formatter.nix
│   ├── shell.nix
│   ├── packages/
│   └── checks.nix
└── [nix modules and configurations...]
```

## Development Workflow

### Stage 1: Initial Setup and Validation

**Setup flake-parts structure:**

```nix
{
  description = "Project description";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      imports = [
        ./nix/formatter.nix  # or ./dev/formatter.nix
        ./nix/shell.nix
        # Add more as needed
      ];
    };
}
```

**Immediate validation commands:**

```bash
# Check flake structure and evaluate outputs
nix flake check

# Format all Nix files
nix fmt

# Validate flake metadata
nix flake metadata
nix flake show
```

Run these checks after any structural changes to catch errors early.

### Stage 2: Core Development (MVP Phase)

**Incremental validation cycle:**

1. Implement core functionality
2. Run `nix fmt` after each significant change
3. Use `nix flake check` to validate outputs
4. For multi-package projects, use nix-fast-build:

   ```bash
   # Build all checks quickly in parallel
   nix run github:Mic92/nix-fast-build -- -f .#checks.x86_64-linux

   # Or for all systems
   nix run github:Mic92/nix-fast-build -- -f .#checks
   ```

**Build and validate core logic:**

```bash
# Build the package
nix build .#packageName

# Test basic functionality
./result/bin/program --version
./result/bin/program --help

# Test core logic manually
./result/bin/program [key commands]
```

**CRITICAL**: Don't just test CLI flags. Verify the actual core logic works:

- For data processing tools: process sample data
- For services: start and check basic operations
- For libraries: run example usage
- For system tools: test primary use cases

### Stage 3: Testing Strategy (Post-Stabilization)

**⚠️ IMPORTANT**: Only introduce unit tests when:

- Core abstractions are stable and unlikely to change
- The API surface is well-defined
- Major refactoring is complete

Early testing can become a maintenance burden as abstractions evolve.

**Testing approaches with Nix:**

1. **Simple validation checks** (checks.nix):

```nix
{ pkgs, myPackage, ... }:
{
  perSystem = { config, pkgs, ... }: {
    checks = {
      # Basic smoke tests
      version-check = pkgs.runCommand "version-check" {} ''
        ${myPackage}/bin/program --version | grep -q "1.0.0"
        touch $out
      '';

      # Verify critical functionality
      core-logic-test = pkgs.runCommand "core-logic" {} ''
        echo "test input" | ${myPackage}/bin/program process > output
        grep -q "expected result" output
        touch $out
      '';
    };
  };
}
```

2. **NixOS Tests for integration testing**:

```nix
{
  checks = {
    integration-test = pkgs.nixosTest {
      name = "service-integration";
      nodes.machine = { pkgs, ... }: {
        imports = [ ./module.nix ];
        services.myservice.enable = true;
      };

      testScript = ''
        machine.wait_for_unit("myservice.service")
        machine.succeed("curl http://localhost:8080/health")
      '';
    };
  };
}
```

3. **Language-specific tests wrapped in Nix**:

```nix
{
  checks = {
    unit-tests = pkgs.runCommand "unit-tests" {
      buildInputs = [ myPackage pkgs.python3 pkgs.pytest ];
    } ''
      cd ${./tests}
      pytest -v
      touch $out
    '';
  };
}
```

## Validation Checklist

### Before Each Commit

- [ ] `nix fmt` - Code is formatted
- [ ] `nix flake check` - All outputs evaluate correctly
- [ ] Core functionality manually tested

### Before Each Release

- [ ] All checks pass: `nix run github:Mic92/nix-fast-build -- -f .#checks`
- [ ] `nix build` succeeds for all packages
- [ ] Runtime behavior validated with real-world scenarios
- [ ] Documentation updated (README, examples)
- [ ] CHANGELOG updated if applicable

### When to Add Tests

- [ ] Abstractions are stable (no major refactoring planned)
- [ ] API surface is finalized
- [ ] Core logic is working reliably
- [ ] You have time to maintain tests during changes

## Common Patterns

### Multi-Package Projects

Use flake-parts to organize multiple packages:

```nix
{
  perSystem = { pkgs, ... }: {
    packages = {
      default = pkgs.callPackage ./nix/packages/main.nix {};
      cli = pkgs.callPackage ./nix/packages/cli.nix {};
      lib = pkgs.callPackage ./nix/packages/lib.nix {};
    };
  };
}
```

Validate all at once:

```bash
nix run github:Mic92/nix-fast-build -- -f .#packages
```

### Development Shells with Tool Integration

```nix
{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        # Language tools
        rustc cargo
        # Nix tools
        nil nixpkgs-fmt
        # Project tools
        just
      ];

      shellHook = ''
        echo "Development environment ready"
        echo "Run 'just build' to build the project"
      '';
    };
  };
}
```

### Formatters

```nix
{
  perSystem = { pkgs, ... }: {
    formatter = pkgs.nixpkgs-fmt;
    # Or use treefmt for multi-language projects
    # formatter = pkgs.treefmt;
  };
}
```

## Troubleshooting

### Flake check fails but manual build works

- Some checks may be too strict during development
- Consider moving strict checks to a separate attribute
- Use `nix flake check --no-build` to skip build checks

### nix-fast-build issues

- Ensure you're using the correct attribute path
- Check that all systems are properly defined
- Use `--skip-cached` to rebuild everything

### Tests become maintenance burden

- This means tests were introduced too early
- Consider removing tests until abstractions stabilize
- Focus on integration tests over unit tests initially

## Best Practices Summary

1. **Validate Early, Validate Often**: Run `nix fmt` and `nix flake check` frequently
2. **Build Before Committing**: Always ensure `nix build` succeeds
3. **Test Real Behavior**: Don't just check --version, test actual functionality
4. **Strategic Testing**: Wait for stability before writing extensive tests
5. **Use Fast Tools**: nix-fast-build for quick multi-package validation
6. **Modular Structure**: Use flake-parts to keep flake.nix clean and maintainable
7. **Document as You Go**: Keep README and examples up to date

## References

- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [flake-parts Documentation](https://flake.parts)
- [nix-fast-build](https://github.com/Mic92/nix-fast-build)
- [NixOS Tests](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)
