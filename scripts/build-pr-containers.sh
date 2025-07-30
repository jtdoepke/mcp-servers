#!/bin/bash
# Build containers for PR validation
# This script builds MCP server containers for pull request validation,
# using the latest version from versions.json with PR-specific tagging.

set -euo pipefail

# Parse command line arguments
SERVER=""
UPSTREAM_REPO=""
VERSIONS=""
PR_NUMBER=""

while [[ $# -gt 0 ]]; do
  case $1 in
  --server)
    SERVER="$2"
    shift 2
    ;;
  --upstream-repo)
    UPSTREAM_REPO="$2"
    shift 2
    ;;
  --versions)
    VERSIONS="$2"
    shift 2
    ;;
  --pr-number)
    PR_NUMBER="$2"
    shift 2
    ;;
  --help)
    echo "Usage: $0 --server SERVER --upstream-repo REPO --versions VERSIONS --pr-number PR"
    echo ""
    echo "Build containers for PR validation"
    echo ""
    echo "Required arguments:"
    echo "  --server SERVER         Server name to build"
    echo "  --upstream-repo REPO    Upstream repository URL"
    echo "  --versions VERSIONS     Multiline versions in format 'version:hash'"
    echo "  --pr-number PR          Pull request number"
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

# Validate required arguments
if [[ -z "$SERVER" || -z "$UPSTREAM_REPO" || -z "$VERSIONS" || -z "$PR_NUMBER" ]]; then
  echo "Error: All arguments are required"
  echo "Use --help for usage information"
  exit 1
fi

echo "Building containers for $SERVER"

# Get the latest version (first in list)
latest_entry=$(echo "$VERSIONS" | head -n1)
version=$(echo "$latest_entry" | cut -d: -f1)
hash=$(echo "$latest_entry" | cut -d: -f2)

echo "Building latest version $SERVER:$version (hash: $hash)"

# Build the container with PR-specific tag
docker build \
  --build-arg "SRC_REPO=$UPSTREAM_REPO" \
  --build-arg "SRC_HASH=$hash" \
  --tag "mcp-$SERVER:pr-$PR_NUMBER" \
  --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY" \
  --label "org.opencontainers.image.revision=$GITHUB_SHA" \
  --label "org.opencontainers.image.version=$version" \
  "src/$SERVER/"

# Export for scanning
docker save "mcp-$SERVER:pr-$PR_NUMBER" \
  -o "$SERVER-pr-$PR_NUMBER.tar"

echo "✅ Container built and exported: mcp-$SERVER:pr-$PR_NUMBER"
