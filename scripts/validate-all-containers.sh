#!/bin/bash
# Validate All Containers Script
#
# This script validates all built MCP server containers for security compliance.
# It can be used in CI/CD pipelines or for local validation.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_PREFIX="${REGISTRY_PREFIX:-ghcr.io/jtdoepke/mcp-servers}"

# Print functions
print_header() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

usage() {
  cat <<EOF
Validate All Containers Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -r, --registry      Registry prefix (default: $REGISTRY_PREFIX)
    --local             Validate local builds instead of registry images
    --server SERVER     Validate specific server only
    --json              Output results in JSON format
    --fail-fast         Stop on first failure

EXAMPLES:
    $0                                  # Validate all registry images
    $0 --local                          # Validate all local builds
    $0 --server sequentialthinking      # Validate specific server
    $0 --json > validation-results.json # JSON output

DESCRIPTION:
    This script discovers all MCP server containers and validates their security
    compliance using the test-container-security.sh script. It can validate
    either local builds or registry images.

EXIT CODES:
    0   All containers passed validation
    1   Some containers failed validation
    2   No containers found to validate
    3   Invalid arguments or configuration
EOF
}

# Find all versions.json files and extract image information
discover_containers() {
  local registry_prefix="$1"
  local local_builds="$2"
  local specific_server="$3"

  local containers=()

  # Find all versions.json files
  for versions_file in "$PROJECT_ROOT"/src/*/versions.json; do
    if [[ ! -f $versions_file ]]; then
      continue
    fi

    local server_name
    server_name=$(basename "$(dirname "$versions_file")")

    # Skip if specific server requested and this isn't it
    if [[ -n $specific_server && $server_name != "$specific_server" ]]; then
      continue
    fi

    print_info "Discovering containers for server: $server_name"

    # Extract versions from versions.json
    while IFS= read -r version; do
      if [[ $local_builds == "true" ]]; then
        # Local build naming convention
        local image_name="$server_name:$version"
      else
        # Registry naming convention
        local image_name="$registry_prefix:$server_name-$version"
      fi

      # Check if image exists locally
      if docker inspect "$image_name" >/dev/null 2>&1; then
        containers+=("$image_name")
        print_info "Found container: $image_name"
      else
        print_warning "Container not found: $image_name"
      fi

    done < <(jq -r '.versions | keys[]' "$versions_file" 2>/dev/null || echo "")

    # Also check for latest tag
    if [[ $local_builds == "true" ]]; then
      local latest_image="$server_name:latest"
    else
      local latest_image="$registry_prefix:$server_name"
    fi

    if docker inspect "$latest_image" >/dev/null 2>&1; then
      containers+=("$latest_image")
      print_info "Found latest container: $latest_image"
    fi
  done

  printf '%s\n' "${containers[@]}"
}

# Validate a single container
validate_container() {
  local image="$1"
  local verbose="$2"
  local json_output="$3"

  local test_script="$SCRIPT_DIR/test-container-security.sh"

  if [[ ! -f $test_script ]]; then
    print_error "Security test script not found: $test_script"
    return 1
  fi

  print_info "Validating: $image"

  # Build test command
  local cmd=("$test_script")
  if [[ $verbose == "true" ]]; then
    cmd+=("--verbose")
  fi
  if [[ $json_output == "true" ]]; then
    cmd+=("--json")
  fi
  cmd+=("$image")

  # Run validation
  local result=0
  "${cmd[@]}" || result=$?

  return $result
}

# Generate summary report
generate_summary() {
  local total="$1"
  local passed="$2"
  local failed="$3"
  local json_output="$4"

  if [[ $json_output == "true" ]]; then
    cat <<EOF
{
  "summary": {
    "total_containers": $total,
    "passed": $passed,
    "failed": $failed,
    "success_rate": "$((passed * 100 / total))%"
  },
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
  else
    print_header "Validation Summary"
    print_info "Total containers: $total"
    print_info "Passed: $passed"
    print_info "Failed: $failed"
    print_info "Success rate: $((passed * 100 / total))%"

    if [[ $failed -eq 0 ]]; then
      print_success "All containers passed security validation"
    else
      print_error "$failed container(s) failed security validation"
    fi
  fi
}

main() {
  local verbose="false"
  local registry_prefix="$REGISTRY_PREFIX"
  local local_builds="false"
  local specific_server=""
  local json_output="false"
  local fail_fast="false"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    -v | --verbose)
      verbose="true"
      shift
      ;;
    -r | --registry)
      registry_prefix="$2"
      shift 2
      ;;
    --local)
      local_builds="true"
      shift
      ;;
    --server)
      specific_server="$2"
      shift 2
      ;;
    --json)
      json_output="true"
      shift
      ;;
    --fail-fast)
      fail_fast="true"
      shift
      ;;
    -*)
      print_error "Unknown option: $1"
      usage
      exit 3
      ;;
    *)
      print_error "Unexpected argument: $1"
      usage
      exit 3
      ;;
    esac
  done

  # Check dependencies
  if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker is required but not installed"
    exit 3
  fi

  if ! command -v jq >/dev/null 2>&1; then
    print_error "jq is required but not installed"
    exit 3
  fi

  if [[ $json_output != "true" ]]; then
    print_header "Container Security Validation"
    print_info "Registry prefix: $registry_prefix"
    print_info "Local builds: $local_builds"
    print_info "Specific server: ${specific_server:-"all"}"
    print_info "Verbose: $verbose"
    print_info "Fail fast: $fail_fast"
  fi

  # Discover containers
  local containers
  mapfile -t containers < <(discover_containers "$registry_prefix" "$local_builds" "$specific_server")

  if [[ ${#containers[@]} -eq 0 ]]; then
    if [[ $json_output == "true" ]]; then
      echo '{"error": "No containers found to validate", "containers": []}'
    else
      print_error "No containers found to validate"
      print_info "Build containers first or check registry access"
    fi
    exit 2
  fi

  if [[ $json_output != "true" ]]; then
    print_info "Found ${#containers[@]} container(s) to validate"
  fi

  # Validate each container
  local total=${#containers[@]}
  local passed=0
  local failed=0
  local validation_results="[]"

  for container in "${containers[@]}"; do
    if [[ $json_output != "true" ]]; then
      print_header "Validating Container: $container"
    fi

    local result=0
    local validation_output

    if [[ $json_output == "true" ]]; then
      validation_output=$(validate_container "$container" "$verbose" "true" 2>&1) || result=$?
    else
      validate_container "$container" "$verbose" "false" || result=$?
    fi

    if [[ $result -eq 0 ]]; then
      ((passed++))
      if [[ $json_output != "true" ]]; then
        print_success "Container validation passed: $container"
      fi
    else
      ((failed++))
      if [[ $json_output != "true" ]]; then
        print_error "Container validation failed: $container"
      fi

      if [[ $fail_fast == "true" ]]; then
        if [[ $json_output != "true" ]]; then
          print_error "Fail-fast enabled, stopping validation"
        fi
        break
      fi
    fi

    # Collect JSON results if needed
    if [[ $json_output == "true" && -n $validation_output ]]; then
      local container_result
      container_result=$(jq -n \
        --arg container "$container" \
        --arg status "$([ $result -eq 0 ] && echo "passed" || echo "failed")" \
        --argjson details "$validation_output" \
        '{container: $container, status: $status, details: $details}')
      validation_results=$(echo "$validation_results" | jq ". += [$container_result]")
    fi
  done

  # Generate summary
  if [[ $json_output == "true" ]]; then
    jq -n \
      --argjson total "$total" \
      --argjson passed "$passed" \
      --argjson failed "$failed" \
      --argjson results "$validation_results" \
      --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{
                summary: {
                    total_containers: $total,
                    passed: $passed,
                    failed: $failed,
                    success_rate: ($passed * 100 / $total | floor)
                },
                timestamp: $timestamp,
                results: $results
            }'
  else
    generate_summary "$total" "$passed" "$failed" "false"
  fi

  # Exit with appropriate code
  if [[ $failed -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"
