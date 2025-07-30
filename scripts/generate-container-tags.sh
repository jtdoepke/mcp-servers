#!/bin/bash
# Generate container tags for MCP server builds
# This script generates multiple tags for container images based on server name,
# version, build date, and optionally release tags for flexible tagging strategy.

set -euo pipefail

# Parse command line arguments
SERVER=""
VERSION=""
BUILD_DATE=""
RELEASE_TAG=""
IMAGE_PREFIX=""

while [[ $# -gt 0 ]]; do
  case $1 in
  --server)
    SERVER="$2"
    shift 2
    ;;
  --version)
    VERSION="$2"
    shift 2
    ;;
  --build-date)
    BUILD_DATE="$2"
    shift 2
    ;;
  --release-tag)
    RELEASE_TAG="$2"
    shift 2
    ;;
  --image-prefix)
    IMAGE_PREFIX="$2"
    shift 2
    ;;
  --help)
    echo "Usage: $0 --server SERVER --version VERSION --image-prefix PREFIX [OPTIONS]"
    echo ""
    echo "Generate container tags for MCP server builds"
    echo ""
    echo "Required arguments:"
    echo "  --server SERVER         Server name"
    echo "  --version VERSION       Server version"
    echo "  --image-prefix PREFIX   Container image prefix (e.g., ghcr.io/user/repo)"
    echo ""
    echo "Optional arguments:"
    echo "  --build-date DATE       Build date (default: current date YYYYMMDD)"
    echo "  --release-tag TAG       Release tag for release builds"
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

# Validate required arguments
if [[ -z "$SERVER" || -z "$VERSION" || -z "$IMAGE_PREFIX" ]]; then
  echo "Error: --server, --version, and --image-prefix are required"
  echo "Use --help for usage information"
  exit 1
fi

# Set default build date if not provided
if [[ -z "$BUILD_DATE" ]]; then
  BUILD_DATE=$(date +%Y%m%d)
fi

echo "Generating tags for: $SERVER $VERSION"

# Generate tags
tags=""
tags="$tags,${IMAGE_PREFIX}:${SERVER}-${VERSION}"
tags="$tags,${IMAGE_PREFIX}:${SERVER}-${VERSION}-${BUILD_DATE}"

# Add release-specific tag if provided
if [[ -n "$RELEASE_TAG" ]]; then
  tags="$tags,${IMAGE_PREFIX}:${SERVER}-${VERSION}-${RELEASE_TAG}"
fi

# Add latest tag for the server
tags="$tags,${IMAGE_PREFIX}:${SERVER}"

# Remove leading comma
tags="${tags#,}"

echo "Generated tags: $tags"

# Set GitHub Actions output if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "tags=$tags" >>"$GITHUB_OUTPUT"
else
  # Output for local testing
  echo "Tags: $tags"
fi
