# arc-config-repo

Configuration repository for GitHub Actions Runner Controller (ARC) scale sets and policies.

This repo is organized for demo purposes and provides comprehensive examples of ARC configurations, validation scripts, and best practices.

## Structure

- **`runners/`** — Runner scale set manifests organized by scope
  - `org-level/` — Organization-wide runner configurations
  - `repo-level/` — Repository-specific runner configurations
- **`policies/`** — Runner usage and network policies
  - `org-level-policy.yaml` — Organization-wide policy settings
  - `repo-level/` — Repository-specific policy overrides
- **`templates/`** — Reusable configuration templates
  - `runner-set-template.yaml` — Generic runner deployment template
  - `policy-template.yaml` — Generic policy configuration template
- **`scripts/`** — Automation and validation scripts
  - `validate-config.sh` — YAML syntax and best practice validation
  - `apply-config.sh` — Configuration deployment script
- **`docs/`** — Documentation and guides
  - `QUICKSTART.md` — Getting started guide
  - `FAQ.md` — Common questions and troubleshooting
- **`.github/workflows/`** — CI/CD automation
  - `validate-config.yml` — Automated validation on pull requests

## Quick Start

1. **Validate configurations**: `./scripts/validate-config.sh -v`
2. **Apply configurations**: `./scripts/apply-config.sh`
3. **Create new runners**: Use templates in `templates/` as starting points

## Features

- ✅ **Automated validation** with GitHub Actions
- ✅ **Security best practices** built into templates
- ✅ **Comprehensive examples** for different use cases
- ✅ **Documentation** for easy setup and troubleshooting
- ✅ **Template-based** configuration for consistency

## Usage

This repository demonstrates:
- Multi-tenancy patterns (org vs repo level)
- Security configurations and best practices
- Resource management and scaling
- Policy-based governance
- CI/CD integration for configuration management

Feel free to use and adapt these samples for your own ARC setup. See the `docs/` folder for detailed guidance.
