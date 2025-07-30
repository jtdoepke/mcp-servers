#!/bin/bash
# Pre-build security validation for MCP server containers
# This script performs comprehensive security validation before building containers:
# 1. Dockerfile security scanning with hadolint
# 2. Non-root user compliance validation
# 3. COPY operation security checks

set -euo pipefail

# Parse command line arguments
DOCKERFILE_PATH=""
while [[ $# -gt 0 ]]; do
  case $1 in
  --dockerfile)
    DOCKERFILE_PATH="$2"
    shift 2
    ;;
  --help)
    echo "Usage: $0 --dockerfile DOCKERFILE_PATH"
    echo ""
    echo "Perform pre-build security validation on a Dockerfile"
    echo ""
    echo "Required arguments:"
    echo "  --dockerfile PATH       Path to the Dockerfile to validate"
    echo ""
    echo "Options:"
    echo "  --help                  Show this help message"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1"
    echo "Use --help for usage information"
    exit 1
    ;;
  esac
done

if [[ -z "$DOCKERFILE_PATH" ]]; then
  echo "Error: --dockerfile argument is required"
  echo "Use --help for usage information"
  exit 1
fi

if [[ ! -f "$DOCKERFILE_PATH" ]]; then
  echo "Error: Dockerfile not found at: $DOCKERFILE_PATH"
  exit 1
fi

echo "=== Pre-build Security Validation ==="
echo "Validating: $DOCKERFILE_PATH"

# Run hadolint with security-focused rules
echo "Running hadolint security check..."
if command -v hadolint >/dev/null 2>&1; then
  hadolint "$DOCKERFILE_PATH" \
    --ignore DL3008 \
    --ignore DL3009 \
    --failure-threshold warning
else
  echo "⚠️ WARNING: hadolint not found, skipping Dockerfile linting"
fi

# Validate non-root requirements
echo "Checking non-root compliance..."

# Check for root user violations
if grep -q "USER root\|USER 0$" "$DOCKERFILE_PATH"; then
  echo "❌ ERROR: Dockerfile contains explicit root user usage"
  exit 1
fi

# Check for non-root base image or USER statement
if grep -q "FROM.*:nonroot" "$DOCKERFILE_PATH"; then
  echo "✅ Using nonroot base image"
elif grep -q "^USER [^0]" "$DOCKERFILE_PATH"; then
  echo "✅ Found non-root USER statement"
else
  echo "❌ ERROR: No non-root execution method found"
  echo "Dockerfile must either:"
  echo "  1. Use a :nonroot base image, or"
  echo "  2. Include a USER statement with non-root user"
  exit 1
fi

# Check for proper --chown usage in COPY statements
if grep -q "COPY --from=" "$DOCKERFILE_PATH"; then
  if ! grep -q "COPY --from=.*--chown=" "$DOCKERFILE_PATH"; then
    echo "⚠️ WARNING: COPY --from operations should include --chown for proper file ownership"
  else
    echo "✅ COPY operations include proper ownership"
  fi
fi

# Additional security checks
echo "Performing additional security checks..."

# Check for ADD with HTTP URLs (security risk)
if grep -q "ADD http:" "$DOCKERFILE_PATH"; then
  echo "❌ ERROR: Using ADD with HTTP URLs (security risk)"
  echo "Use COPY with downloaded files or HTTPS URLs instead"
  exit 1
fi

# Check for passwords or secrets in environment variables
if grep -i -E "(password|secret|key|token)=" "$DOCKERFILE_PATH"; then
  echo "⚠️ WARNING: Potential secrets detected in Dockerfile"
  echo "Ensure no sensitive information is hardcoded"
fi

# Check for use of sudo (shouldn't be needed in containers)
if grep -q "sudo " "$DOCKERFILE_PATH"; then
  echo "⚠️ WARNING: sudo usage detected in Dockerfile"
  echo "Consider using proper USER statements instead"
fi

echo "✅ Pre-build security validation passed"
