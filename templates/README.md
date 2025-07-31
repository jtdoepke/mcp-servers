# Security-First Dockerfile Templates

This directory contains security-focused Dockerfile templates for MCP servers. All templates follow the project's strict non-root security requirements.

## Security Standards

All templates in this directory adhere to these security requirements:

### ✅ **Non-Root Execution** (MANDATORY)
- All containers **MUST** run as a non-root user, never root
- Preferred: UID 65532 (nobody) but any non-root user is acceptable
- Either use `:nonroot` base images OR explicit `USER` statement with non-root user

### ✅ **File Ownership**
- All files **MUST** be owned by the runtime user
- Use `--chown` parameter in `COPY` operations
- Format: `COPY --from=builder --chown=65532:65532 source dest`

### ✅ **Multi-Stage Builds**
- Builder stage can use root (for package installation)
- Runtime stage **MUST** be non-root
- Clean separation between build and runtime environments

### ✅ **Minimal Attack Surface**
- Distroless images preferred (no shell, no package managers)
- Slim images acceptable with explicit non-root user creation
- No unnecessary packages or tools in runtime stage

## Available Templates

### Node.js Templates

#### `Dockerfile.nodejs-distroless` (Recommended)
- **Base**: `gcr.io/distroless/nodejs24-debian12:nonroot`
- **User**: UID 65532 (built-in nonroot user)
- **Security**: Maximum (no shell, minimal packages)
- **Use Case**: Production MCP servers requiring highest security

#### `Dockerfile.nodejs-slim` (Alternative)
- **Base**: `node:24-slim`
- **User**: Custom nodejs user (UID 1001)
- **Security**: High (has shell for debugging)
- **Use Case**: Development or when shell access needed

### Python Templates

#### `Dockerfile.python-distroless` (Recommended)
- **Base**: `gcr.io/distroless/python3-debian12:nonroot`
- **User**: UID 65532 (built-in nonroot user)
- **Security**: Maximum (no shell, minimal packages)
- **Use Case**: Production Python MCP servers

## Usage Instructions

### 1. Copy Template
```bash
# Copy the appropriate template to your server directory
cp templates/Dockerfile.nodejs-distroless src/your-server/Dockerfile
```

### 2. Customize for Your Server
Edit the copied Dockerfile and update:
- `ARG SRC_REPO=` - Set to your upstream repository URL
- Uncomment and adjust `WORKDIR` if using monorepo structure
- Update build commands (npm run build, pip install, etc.)
- Adjust `ENTRYPOINT` for your server's main script

### 3. Validate Security Compliance
```bash
# Run pre-commit hooks to validate security
pre-commit run dockerfile-security-check --files src/your-server/Dockerfile
pre-commit run dockerfile-nonroot-validation --files src/your-server/Dockerfile
```

### 4. Test Build
```bash
# Test build with your upstream repo and commit hash
docker build \
  --build-arg SRC_REPO=https://github.com/your-org/your-repo \
  --build-arg SRC_HASH=abc123commitHash \
  -t test-server:latest \
  src/your-server/
```

### 5. Validate Non-Root Execution
```bash
# Verify container runs as non-root
docker run --rm test-server:latest whoami
# Should NOT return "root"

# Check container user configuration
docker inspect test-server:latest --format='{{.Config.User}}'
# Should show non-root user (e.g., "65532" or "nodejs")
```

## Security Validation Checklist

Before using any Dockerfile, ensure it passes these checks:

- [ ] ✅ Uses non-root base image (`:nonroot`) OR has explicit `USER` statement
- [ ] ✅ No `USER root` or `USER 0` statements in runtime stage
- [ ] ✅ All `COPY` operations use `--chown` with non-root user
- [ ] ✅ Container inspection shows non-root user
- [ ] ✅ `docker run --rm image whoami` returns non-root user
- [ ] ✅ Pre-commit hooks pass without errors
- [ ] ✅ Multi-stage build separates concerns properly

## Template Customization Examples

### Monorepo Structure
```dockerfile
# After git clone and checkout
WORKDIR /repo/src/your-server-name

# Continue with build process...
```

### Custom Build Process
```dockerfile
# For servers with custom build steps
RUN npm install
RUN npm run build:custom
RUN npm run test  # Optional: run tests during build
```

### Health Checks
```dockerfile
# Add health check for better container monitoring
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node health-check.js || exit 1
```

## Security Best Practices

### DO ✅
- Use Distroless base images when possible
- Set explicit non-root `USER` statement
- Use `--chown` in all `COPY` operations
- Pin base image versions with SHA hashes
- Use multi-stage builds
- Run security validation before deployment

### DON'T ❌
- Use `USER root` or `USER 0` in runtime stage
- Copy files without proper ownership (`--chown`)
- Use `ADD` with HTTP URLs
- Install unnecessary packages in runtime stage
- Run containers as root user
- Skip security validation steps

## Troubleshooting

### "Permission Denied" Errors
- Ensure all files are owned by the runtime user
- Check that `--chown` is used in all `COPY` operations
- Verify the user has proper permissions for the working directory

### Container Won't Start
- Check that the entrypoint script exists and is executable
- Verify the runtime user has access to required files
- Ensure NODE_PATH or PYTHONPATH is set correctly

### Security Validation Failures
- Review pre-commit hook output for specific errors
- Ensure no `USER root` statements in runtime stage
- Verify base image uses `:nonroot` variant OR has explicit USER statement

## Support

For questions about these templates or security requirements:
1. Check the main project documentation in `CLAUDE.md`
2. Review security validation in `.pre-commit-config.yaml`
3. Examine working examples in `src/*/Dockerfile`
