#!/bin/bash
# Generate build matrix from versions.json files for GitHub Actions
# This script scans all src/*/versions.json files and generates a JSON matrix
# for building containers with specified versions and commit hashes.

set -euo pipefail

# Parse command line arguments
SPECIFIC_SERVER=""
while [[ $# -gt 0 ]]; do
  case $1 in
  --server)
    SPECIFIC_SERVER="$2"
    shift 2
    ;;
  --help)
    echo "Usage: $0 [--server SERVER_NAME]"
    echo ""
    echo "Generate build matrix from versions.json files"
    echo ""
    echo "Options:"
    echo "  --server SERVER_NAME    Only include specific server in matrix"
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

echo "Generating build matrix from versions.json files..."

matrix_json="[]"
has_builds="false"

# Find all versions.json files in src/ subdirectories
for versions_file in src/*/versions.json; do
  if [[ ! -f "$versions_file" ]]; then
    continue
  fi

  server_name=$(basename "$(dirname "$versions_file")")
  echo "Processing server: $server_name"

  # Skip if specific server requested and this isn't it
  if [[ -n "$SPECIFIC_SERVER" && "$server_name" != "$SPECIFIC_SERVER" ]]; then
    echo "Skipping $server_name (not the requested specific server)"
    continue
  fi

  # Extract upstream repo and versions using jq
  upstream_repo=$(jq -r '.upstream_repo' "$versions_file")

  # Process each version
  while IFS= read -r version; do
    commit_hash=$(jq -r ".versions.\"$version\"" "$versions_file")

    if [[ "$commit_hash" == "null" || -z "$commit_hash" ]]; then
      echo "Skipping $server_name $version: no commit hash"
      continue
    fi

    echo "Adding to matrix: $server_name $version ($commit_hash)"

    # Add to matrix JSON
    matrix_item=$(jq -n \
      --arg server "$server_name" \
      --arg version "$version" \
      --arg hash "$commit_hash" \
      --arg repo "$upstream_repo" \
      '{
        server: $server,
        version: $version,
        commit_hash: $hash,
        upstream_repo: $repo,
        dockerfile_path: ("src/" + $server + "/Dockerfile")
      }')

    matrix_json=$(echo "$matrix_json" | jq ". += [$matrix_item]")
    has_builds="true"

  done < <(jq -r '.versions | keys[]' "$versions_file")
done

echo "Final matrix JSON:"
echo "$matrix_json" | jq '.'

# Set GitHub Actions outputs if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "matrix={\"include\":$matrix_json}" >>"$GITHUB_OUTPUT"
  echo "has_builds=$has_builds" >>"$GITHUB_OUTPUT"
else
  # Output for local testing
  echo "Matrix: {\"include\":$matrix_json}"
  echo "Has builds: $has_builds"
fi
