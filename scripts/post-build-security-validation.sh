#!/bin/bash
# Post-build security validation for MCP server containers
# This script performs comprehensive security validation after building containers:
# 1. Container user configuration verification
# 2. Runtime user validation
# 3. Container startup testing

set -euo pipefail

# Parse command line arguments
IMAGE_TAG=""
while [[ $# -gt 0 ]]; do
  case $1 in
  --image)
    IMAGE_TAG="$2"
    shift 2
    ;;
  --help)
    echo "Usage: $0 --image IMAGE_TAG"
    echo ""
    echo "Perform post-build security validation on a container image"
    echo ""
    echo "Required arguments:"
    echo "  --image TAG             Container image tag to validate"
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

if [[ -z "$IMAGE_TAG" ]]; then
  echo "Error: --image argument is required"
  echo "Use --help for usage information"
  exit 1
fi

echo "=== Post-build Security Validation ==="
echo "Testing container: $IMAGE_TAG"

# Verify the image exists
if ! docker inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "❌ ERROR: Container image not found: $IMAGE_TAG"
  exit 1
fi

# Inspect container to verify user configuration
echo "Checking container user configuration..."
user_info=$(docker inspect "$IMAGE_TAG" --format='{{.Config.User}}')

if [[ "$user_info" == "0" || "$user_info" == "root" || -z "$user_info" ]]; then
  # For containers with empty user, check if base image is nonroot
  base_image=$(docker inspect "$IMAGE_TAG" --format='{{index .Config.Image}}' | head -1 || echo "")
  if [[ "$base_image" == *":nonroot"* ]]; then
    echo "✅ Using nonroot base image"
  else
    echo "❌ ERROR: Container may run as root (User: '$user_info')"
    echo "Container configuration shows potential root execution"
    exit 1
  fi
else
  echo "✅ Container configured with non-root user: $user_info"
fi

# Test runtime user by running whoami in container
echo "Testing runtime user..."
runtime_user=$(docker run --rm "$IMAGE_TAG" whoami 2>/dev/null || echo "unknown")

if [[ "$runtime_user" == "root" ]]; then
  echo "❌ ERROR: Container runs as root user at runtime"
  echo "Runtime user: $runtime_user"
  exit 1
elif [[ "$runtime_user" == "unknown" ]]; then
  echo "⚠️ WARNING: Could not determine runtime user (container may not support whoami command)"

  # Alternative check: try to access /root directory
  if docker run --rm "$IMAGE_TAG" sh -c "test -w /root" 2>/dev/null; then
    echo "❌ ERROR: Container has write access to /root (likely running as root)"
    exit 1
  else
    echo "✅ Container does not have write access to /root (likely non-root)"
  fi
else
  echo "✅ Container runs as non-root user: $runtime_user"
fi

# Test that container starts successfully
echo "Testing container startup..."
timeout 10s docker run --rm "$IMAGE_TAG" --help >/dev/null 2>&1 || {
  echo "⚠️ WARNING: Container startup test failed (may be expected for some servers)"
  echo "This could indicate:"
  echo "  - Server doesn't support --help flag"
  echo "  - Server requires specific configuration"
  echo "  - Server exits immediately without arguments"
  echo "This is not necessarily a security issue"
}

# Additional security checks
echo "Performing additional runtime security checks..."

# Check if container can access privileged operations
if docker run --rm "$IMAGE_TAG" sh -c "mount 2>/dev/null || true" | grep -q "/"; then
  echo "❌ ERROR: Container can perform mount operations (possible privilege escalation)"
  exit 1
fi

# Check for suspicious processes or capabilities
echo "Checking container process capabilities..."
container_id=$(docker run -d "$IMAGE_TAG" sleep 30 2>/dev/null || echo "")
if [[ -n "$container_id" ]]; then
  # Check effective user ID
  effective_uid=$(docker exec "$container_id" id -u 2>/dev/null || echo "unknown")
  if [[ "$effective_uid" == "0" ]]; then
    echo "❌ ERROR: Container is running with UID 0 (root)"
    docker stop "$container_id" >/dev/null 2>&1 || true
    docker rm "$container_id" >/dev/null 2>&1 || true
    exit 1
  elif [[ "$effective_uid" != "unknown" ]]; then
    echo "✅ Container running with non-root UID: $effective_uid"
  fi

  # Clean up test container
  docker stop "$container_id" >/dev/null 2>&1 || true
  docker rm "$container_id" >/dev/null 2>&1 || true
fi

echo "✅ Post-build security validation passed"
