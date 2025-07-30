# Current Understanding: MCP Server Containerization Project

## Project Overview
This is a security-focused repository that builds Docker containers for MCP (Model Context Protocol) servers as an alternative to direct npm installations. The project emphasizes supply chain security, automated version management, and daily security updates through base image rebuilds.

## Key Architecture Components

### Directory Structure
- `src/{server-name}/` - Individual MCP server implementations with Dockerfiles and versions.json
- `scripts/` - Security verification and automation utilities
- `.github/workflows/` - CI/CD workflows for security scanning and automated builds
- `docker-compose.yml` - Container orchestration (placeholder)

### Version Management System
Each server has a `versions.json` configuration file:
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

## Critical Security Requirements

### Non-Root Container Execution
- **MANDATORY**: All containers must run as non-root user, never root
- **Flexible Base Images**: Any base image acceptable (including root-based) if USER is changed to non-root
- **Preferred User**: UID 65532 (nobody) preferred but any non-root user acceptable
- **File Ownership**: All files must be owned by the runtime user with `--chown` in COPY operations

### Current Implementation Status

#### sequentialthinking Server
- **Dockerfile Location**: `src/sequentialthinking/Dockerfile`
- **Base Image**: `gcr.io/distroless/nodejs24-debian12:debug-nonroot` ✅
- **Critical Issues Identified**:
  - Git clone operation targets wrong repo structure for monorepo
  - COPY operations overwrite cloned source incorrectly
  - Missing proper subdirectory handling for modelcontextprotocol/servers repo
- **Upstream**: https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking

#### Security Infrastructure
- **Pre-commit Hooks**: Comprehensive security scanning including:
  - Gitleaks for secret detection
  - Hadolint for Dockerfile security
  - Custom dockerfile-security-check prevents `USER root`
  - Shellcheck for script validation
- **GitHub Actions**: Placeholder workflows need complete implementation

## Automation Requirements

### Version Discovery & PR Creation
- Query GitHub releases API for new versions
- Fallback to git tags with semver patterns
- Filter against excluded versions/hashes
- Auto-create PRs assigned to @jtdoepke
- Include security validation in PR process

### Daily Security Rebuilds
- Build all approved versions with latest base images
- Multi-stage security validation pipeline
- Container signing with cosign
- Multi-tag strategy for tracking (latest, version-specific, date-tagged)
- Publish to GitHub Container Registry

## Container Registry Strategy
All containers published to `ghcr.io/jtdoepke/mcp-servers` with tags:
- `{server-name}` (latest approved version)
- `{server-name}-v{version}` (specific version)
- `{server-name}-v{version}-{YYYYMMDD}` (build date tracking)

## Implementation Plan Status

### Phase 1: Fix Core Infrastructure (CRITICAL)
- [ ] Fix sequentialthinking Dockerfile for monorepo structure
- [ ] Create sequentialthinking versions.json
- [ ] Enforce non-root security standards

### Phase 2: Build Automation Scripts (HIGH)
- [ ] Version discovery script (`scripts/discover-versions.py`)
- [ ] PR creation script (`scripts/create-version-pr.py`)
- [ ] Matrix generation with security validation

### Phase 3: GitHub Actions Workflows (HIGH)
- [ ] Complete daily rebuild workflow with security enforcement
- [ ] Enhanced security scanning pipeline
- [ ] Container runtime security testing

### Phase 4: Templates & Enforcement (MEDIUM)
- [ ] Security-first Dockerfile templates
- [ ] Enhanced pre-commit hook validation
- [ ] Container security testing tools

### Phase 5: Documentation & Compliance (MEDIUM)
- [ ] Security-focused documentation updates
- [ ] Compliance verification and reporting

## Security Validation Pipeline
```dockerfile
# Preferred approach (Distroless nonroot base)
FROM gcr.io/distroless/nodejs24-debian12:nonroot
USER 65532

# Alternative approach (root base with user change)
FROM node:24-slim
RUN adduser --system --uid 1001 nodejs
USER nodejs
```

## Key Files Status
- **CLAUDE.md**: ✅ Complete - Comprehensive documentation for future Claude instances
- **plan.md**: ✅ Complete - Detailed 5-phase implementation plan
- **src/sequentialthinking/Dockerfile**: ❌ Critical issues need fixing
- **.github/workflows/releases.yml**: ❌ Placeholder needing complete rewrite
- **.pre-commit-config.yaml**: ✅ Good foundation with security focus
- **scripts/verify_commit.sh**: ✅ Exists for manual verification

## Next Priority Actions
1. Fix sequentialthinking Dockerfile for proper monorepo handling
2. Create sequentialthinking versions.json with upstream releases
3. Implement version discovery automation scripts
4. Build complete GitHub Actions workflows with security validation

## Security Compliance
- All commits must be signed and verified
- Containers must pass non-root execution validation
- Pre-commit hooks prevent security violations
- Daily rebuilds ensure latest security patches
- Container signing and verification with cosign
