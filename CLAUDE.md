# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository builds Docker containers for MCP (Model Context Protocol) servers as a security-focused alternative to direct npm installations. The project prioritizes supply chain security, automated version management, and daily security updates through base image rebuilds.

## Architecture

### Directory Structure
- **src/{server-name}/** - Individual MCP server implementations, each with its own Dockerfile and versions.json
- **scripts/** - Utility scripts for security verification and automation
- **docker-compose.yml** - Container orchestration (placeholder)
- **.github/workflows/** - CI/CD workflows for security scanning, automated builds, and version discovery

### Version Management System
Each MCP server has its own `versions.json` configuration file at `src/{server-name}/versions.json`:

```json
{
  "upstream_repo": "https://github.com/example/mcp-server-repo",
  "versions": {
    "v1.0.0": "abc123commitHash",
    "v1.1.0": "def456commitHash"
  },
  "excluded_versions": ["v1.2.3"],
  "excluded_hashes": ["badcommithash123"]
}
```

- **versions**: Approved versions that will be built into containers (manually curated)
- **excluded_versions/excluded_hashes**: Prevents auto-discovery script from creating PRs for known problematic releases

## Development Commands

### Local Container Building
```bash
# Build a specific server version
docker build \
  --build-arg SRC_REPO=https://github.com/example/mcp-server \
  --build-arg SRC_HASH=abc123hash \
  -t mcp-server-name:version \
  src/server-name/

# Build using docker-compose (when configured)
docker-compose build server-name
```

### Testing Containers Locally
```bash
# Run a container to test functionality
docker run --rm -it mcp-server-name:version

# Test with MCP client connection
docker run --rm -p 3000:3000 mcp-server-name:version
```

### Security Validation
```bash
# Setup pre-commit hooks for security scanning
pre-commit install

# Run security checks manually
pre-commit run --all-files

# Verify a commit signature from GitHub
./scripts/verify_commit.sh owner/repo commit-sha

# Lint Dockerfiles for security best practices
hadolint src/*/Dockerfile
```

## Automation Workflows

### Version Discovery & PR Creation
The automated version discovery system:
1. Checks GitHub releases API for new versions
2. Falls back to checking git tags with version patterns (semver)
3. Filters against `excluded_versions` and `excluded_hashes`
4. Creates PRs to add new versions to the `versions.json` file
5. Auto-assigns PRs to @jtdoepke for review

### Daily Security Rebuilds
GitHub Actions runs daily to:
1. Read all `versions.json` files across all servers
2. Build every approved version with latest base images
3. Scan containers for vulnerabilities
4. Sign containers with cosign
5. Push to GitHub Container Registry

## Container Registry & Tagging

All containers are published to GitHub Container Registry with multiple tags:

```bash
# Latest approved version
ghcr.io/jtdoepke/mcp-servers:sequentialthinking

# Specific version
ghcr.io/jtdoepke/mcp-servers:sequentialthinking-v1.0.0

# Version with build date (for tracking security updates)
ghcr.io/jtdoepke/mcp-servers:sequentialthinking-v1.0.0-20250130
```

### Container Security Features
- **Multi-stage builds**: less secure builder stage + secure runtime (preferably Distroless)
- **Non-root execution**: **REQUIRED** - All containers must run as a non-root user, never root (UID 65532 preferred)
- **Minimal attack surface**: Distroless base images preferred with no shell or package managers
- **Signed containers**: All images signed with cosign for verification
- **Vulnerability scanning**: Automated security scanning before publication

## GitHub Actions Configuration

### Daily Rebuild Workflow (`.github/workflows/releases.yml`)
- **Trigger**: Daily schedule (respects GitHub free tier limits)
- **Matrix strategy**: Dynamically generated from all `versions.json` files
- **Security pipeline**: Base image verification, vulnerability scanning, container signing
- **Registry**: Pushes to GitHub Container Registry with multi-tag strategy

### PR Automation Workflow
- **Trigger**: Scheduled version discovery
- **Process**: API checks → exclusion filtering → PR creation
- **Assignment**: Auto-assigns @jtdoepke for review
- **Verification**: Only creates PRs for versions with valid upstream commits

## Security Requirements

### Commit Verification
- **This repository**: All commits must be signed and verified
- **Upstream sources**: No verification required (source is pinned to specific commit hashes)
- **Pre-commit hooks**: Comprehensive security scanning including secret detection, Dockerfile linting

### Container Supply Chain Security
- **Source pinning**: All MCP servers built from specific commit hashes
- **Base image verification**: Cosign verification of base images (Distroless preferred)
- **Non-root enforcement**: All containers must run as non-root user (any base image acceptable if USER is changed)
- **Dependency scanning**: Vulnerability scanning before image publication
- **Image signing**: All published containers signed with cosign

### Security Exclusion Process
When upstream versions are discovered to have security issues:
1. Add version/hash to `excluded_versions` or `excluded_hashes` in relevant `versions.json`
2. Remove from `versions` object if already approved
3. Auto-discovery will skip these in future PR creation

## Adding New MCP Servers

1. Create directory under `src/new-server-name/`
2. Add Dockerfile following the multi-stage security pattern with **non-root requirements**:
  - Preferred: Use `gcr.io/distroless/` base images
  - Alternative: Any base image with explicit `USER` change to non-root
  - All COPY operations must include `--chown` with the runtime user
  - Container must run as non-root user, never root (UID 65532 preferred)
3. Create `versions.json` with upstream repository and initial version
4. Update GitHub Actions matrix (auto-detected from config files)
5. Test local build and security scanning, including non-root validation

## Key Files

- `src/*/versions.json` - Version configuration and exclusion lists for each server
- `src/*/Dockerfile` - Multi-stage container definitions with security focus
- `.github/workflows/releases.yml` - Daily rebuild pipeline with security controls
- `.pre-commit-config.yaml` - Comprehensive security scanning hooks
- `scripts/verify_commit.sh` - Manual commit signature verification utility
