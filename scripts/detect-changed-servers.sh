#!/bin/bash
# Detect modified MCP servers from changed files
# This script processes a list of changed files and determines which
# MCP servers have been modified, generating a build matrix for GitHub Actions.

set -euo pipefail

# Parse command line arguments
CHANGED_FILES=""
while [[ $# -gt 0 ]]; do
  case $1 in
  --changed-files)
    CHANGED_FILES="$2"
    shift 2
    ;;
  --help)
    echo "Usage: $0 --changed-files \"file1 file2 file3\""
    echo ""
    echo "Detect modified MCP servers from changed files"
    echo ""
    echo "Required arguments:"
    echo "  --changed-files FILES   Space-separated list of changed files"
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

if [[ -z "$CHANGED_FILES" ]]; then
  echo "Error: --changed-files argument is required"
  echo "Use --help for usage information"
  exit 1
fi

echo "Modified directories: $CHANGED_FILES"

# Extract server names from modified paths
servers=""
matrix_json='{"include":['
first=true

for dir in $CHANGED_FILES; do
  if [[ "$dir" =~ ^src/([^/]+)$ ]]; then
    server_name="${BASH_REMATCH[1]}"
    if [ -f "src/$server_name/versions.json" ]; then
      servers="$servers $server_name"

      # Build matrix entry
      if [ "$first" = false ]; then
        matrix_json+=','
      fi
      matrix_json+="{\"server\":\"$server_name\"}"
      first=false
    fi
  fi
done

matrix_json+=']}'

if [ -z "$servers" ]; then
  echo "No server modifications detected"

  # Set GitHub Actions outputs if running in GitHub Actions
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "servers=" >>"$GITHUB_OUTPUT"
    echo "matrix={\"include\":[]}" >>"$GITHUB_OUTPUT"
  else
    echo "Servers: (none)"
    echo "Matrix: {\"include\":[]}"
  fi
else
  echo "Modified servers:$servers"

  # Set GitHub Actions outputs if running in GitHub Actions
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "servers=$servers" >>"$GITHUB_OUTPUT"
    echo "matrix=$matrix_json" >>"$GITHUB_OUTPUT"
  else
    echo "Servers:$servers"
    echo "Matrix: $matrix_json"
  fi
fi
