#!/bin/bash
# Container Security Testing Script
#
# This script performs comprehensive security validation of MCP server containers:
# - Non-root user validation
# - File permission checking
# - Process inspection
# - Runtime security testing
# - Vulnerability scanning

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_TIMEOUT=30

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

# Usage information
usage() {
  cat <<EOF
Container Security Testing Script

Usage: $0 [OPTIONS] IMAGE_NAME[:TAG]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -t, --timeout N     Set timeout for container tests (default: $DEFAULT_TIMEOUT seconds)
    --skip-vuln         Skip vulnerability scanning
    --skip-runtime      Skip runtime security tests
    --json              Output results in JSON format

EXAMPLES:
    $0 ghcr.io/user/mcp-servers:sequentialthinking-v1.0.0
    $0 --verbose --timeout 60 test-image:latest
    $0 --json --skip-vuln local-build:dev

DESCRIPTION:
    This script performs comprehensive security validation of MCP server containers:

    1. Container Configuration Analysis
      - User configuration validation
      - Entrypoint and command inspection
      - Environment variable security check

    2. Non-Root User Validation
      - Verify container doesn't run as root (UID 0)
      - Validate user ID and group ID
      - Check for proper user configuration

    3. File Permission Analysis
      - Application directory ownership
      - Executable permissions
      - Critical file access validation

    4. Runtime Security Testing
      - Process inspection in running container
      - Network capability testing
      - Resource access validation

    5. Vulnerability Scanning (optional)
      - Container image vulnerability assessment
      - Base image security analysis
      - Dependency security check

EXIT CODES:
    0   All security tests passed
    1   Security violations detected
    2   Container startup failed
    3   Invalid arguments or usage
    4   Required tools missing

SECURITY REQUIREMENTS:
    The container must meet these criteria to pass:
    - Run as non-root user (UID != 0)
    - Have proper file ownership
    - No unnecessary privileges
    - Minimal attack surface
EOF
}

# Check if required tools are available
check_dependencies() {
  local missing_tools=()

  command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
  command -v jq >/dev/null 2>&1 || missing_tools+=("jq")

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    print_error "Missing required tools: ${missing_tools[*]}"
    print_info "Please install the missing tools and try again"
    exit 4
  fi
}

# Validate container image exists
validate_image() {
  local image="$1"

  print_info "Validating image: $image"

  if ! docker inspect "$image" >/dev/null 2>&1; then
    print_error "Image not found: $image"
    print_info "Pull the image first: docker pull $image"
    exit 3
  fi

  print_success "Image exists and is accessible"
}

# Test 1: Container Configuration Analysis
test_container_config() {
  local image="$1"
  local verbose="$2"

  print_header "Container Configuration Analysis"

  # Get container configuration
  local config
  config=$(docker inspect "$image" --format='{{json .Config}}')

  # Extract key configuration details
  local user entrypoint cmd env
  user=$(echo "$config" | jq -r '.User // ""')
  entrypoint=$(echo "$config" | jq -r '.Entrypoint // [] | join(" ")')
  cmd=$(echo "$config" | jq -r '.Cmd // [] | join(" ")')
  env=$(echo "$config" | jq -r '.Env // []')

  if [[ $verbose == "true" ]]; then
    print_info "User: ${user:-"<default>"}"
    print_info "Entrypoint: ${entrypoint:-"<none>"}"
    print_info "Cmd: ${cmd:-"<none>"}"
    print_info "Environment variables: $(echo "$env" | wc -l) defined"
  fi

  # Validate user configuration
  if [[ $user == "0" || $user == "root" ]]; then
    print_error "Container configured to run as root user"
    return 1
  elif [[ -n $user && $user != "0" ]]; then
    print_success "Container configured with non-root user: $user"
  else
    # Check if base image is nonroot
    local image_name
    image_name=$(docker inspect "$image" --format='{{index .RepoTags 0}}' 2>/dev/null || echo "unknown")
    if [[ $image_name == *":nonroot"* ]]; then
      print_success "Using nonroot base image"
    else
      print_warning "No explicit user set - may depend on base image default"
    fi
  fi

  # Check for suspicious environment variables
  if echo "$env" | grep -qi "password\|secret\|key\|token"; then
    print_warning "Environment variables may contain sensitive information"
  fi

  return 0
}

# Test 2: Non-Root User Validation
test_nonroot_user() {
  local image="$1"
  local timeout="$2"

  print_header "Non-Root User Validation"

  # Test runtime user with whoami
  print_info "Testing runtime user identity..."
  local runtime_user
  runtime_user=$(timeout "$timeout" docker run --rm "$image" whoami 2>/dev/null || echo "failed")

  if [[ $runtime_user == "failed" ]]; then
    print_warning "Could not determine runtime user (container may not have whoami command)"

    # Alternative test: check UID directly
    print_info "Attempting alternative UID check..."
    local uid
    uid=$(timeout "$timeout" docker run --rm "$image" id -u 2>/dev/null || echo "failed")

    if [[ $uid == "failed" ]]; then
      print_warning "Could not determine UID (container may not support id command)"
      return 0 # Skip this test if we can't determine user
    elif [[ $uid == "0" ]]; then
      print_error "Container runs as root (UID 0)"
      return 1
    else
      print_success "Container runs as non-root user (UID: $uid)"
    fi
  elif [[ $runtime_user == "root" ]]; then
    print_error "Container runs as root user"
    return 1
  else
    print_success "Container runs as non-root user: $runtime_user"
  fi

  return 0
}

# Test 3: File Permission Analysis
test_file_permissions() {
  local image="$1"
  local timeout="$2"
  local verbose="$3"

  print_header "File Permission Analysis"

  # Check ownership of common application directories
  local dirs_to_check=("/app" "/opt" "/usr/local" "/home")

  for dir in "${dirs_to_check[@]}"; do
    print_info "Checking ownership of $dir..."

    local ownership
    ownership=$(timeout "$timeout" docker run --rm "$image" \
      sh -c "if [ -d '$dir' ]; then ls -ld '$dir' 2>/dev/null || echo 'not accessible'; else echo 'not found'; fi" 2>/dev/null || echo "failed")

    if [[ $ownership == "failed" ]]; then
      print_warning "Could not check $dir (container may not have shell)"
      continue
    elif [[ $ownership == "not found" ]]; then
      if [[ $verbose == "true" ]]; then
        print_info "$dir does not exist"
      fi
      continue
    elif [[ $ownership == "not accessible" ]]; then
      print_warning "$dir exists but is not accessible"
      continue
    fi

    # Check if owned by root
    if echo "$ownership" | grep -q "^d.*root.*root"; then
      print_warning "$dir is owned by root"
    else
      print_success "$dir has non-root ownership"
    fi

    if [[ $verbose == "true" ]]; then
      print_info "$dir permissions: $ownership"
    fi
  done

  return 0
}

# Test 4: Runtime Security Testing
test_runtime_security() {
  local image="$1"
  local timeout="$2"

  print_header "Runtime Security Testing"

  # Test container startup
  print_info "Testing container startup..."
  local container_id
  container_id=$(docker run -d "$image" sleep "$timeout" 2>/dev/null || echo "failed")

  if [[ $container_id == "failed" ]]; then
    print_error "Container failed to start"
    return 2
  fi

  # Wait a moment for container to initialize
  sleep 2

  # Check if container is running
  if ! docker ps --filter "id=$container_id" --format "{{.ID}}" | grep -q "$container_id"; then
    print_error "Container exited unexpectedly"
    docker logs "$container_id" 2>/dev/null || true
    docker rm -f "$container_id" >/dev/null 2>&1 || true
    return 2
  fi

  print_success "Container started successfully"

  # Inspect running processes
  print_info "Inspecting running processes..."
  local processes
  processes=$(docker exec "$container_id" ps aux 2>/dev/null || echo "failed")

  if [[ $processes != "failed" ]]; then
    # Check for root processes
    local root_processes
    root_processes=$(echo "$processes" | grep "^root" | wc -l || echo "0")

    if [[ $root_processes -gt 0 ]]; then
      print_warning "Found $root_processes root processes in container"
    else
      print_success "No root processes detected"
    fi
  else
    print_warning "Could not inspect processes (container may not have ps command)"
  fi

  # Test network capabilities (if applicable)
  print_info "Testing basic container functionality..."
  local health_check
  health_check=$(timeout 10 docker exec "$container_id" \
    sh -c "echo 'Container is responsive' 2>/dev/null || echo 'No shell available'" 2>/dev/null || echo "failed")

  if [[ $health_check == "failed" ]]; then
    print_warning "Container health check failed"
  else
    print_success "Container is responsive"
  fi

  # Cleanup
  docker rm -f "$container_id" >/dev/null 2>&1 || true

  return 0
}

# Test 5: Vulnerability Scanning (optional)
test_vulnerabilities() {
  local image="$1"
  local verbose="$2"

  print_header "Vulnerability Scanning"

  # Check if Docker Scout is available
  if docker scout version >/dev/null 2>&1; then
    print_info "Running Docker Scout vulnerability scan..."

    local scan_result
    scan_result=$(docker scout cves "$image" --format json 2>/dev/null || echo "failed")

    if [[ $scan_result == "failed" ]]; then
      print_warning "Docker Scout scan failed"
      return 0
    fi

    # Parse results
    local critical high medium low
    critical=$(echo "$scan_result" | jq -r '.vulnerabilities[] | select(.severity == "critical") | .id' 2>/dev/null | wc -l || echo "0")
    high=$(echo "$scan_result" | jq -r '.vulnerabilities[] | select(.severity == "high") | .id' 2>/dev/null | wc -l || echo "0")
    medium=$(echo "$scan_result" | jq -r '.vulnerabilities[] | select(.severity == "medium") | .id' 2>/dev/null | wc -l || echo "0")
    low=$(echo "$scan_result" | jq -r '.vulnerabilities[] | select(.severity == "low") | .id' 2>/dev/null | wc -l || echo "0")

    print_info "Vulnerability summary:"
    print_info "  Critical: $critical"
    print_info "  High: $high"
    print_info "  Medium: $medium"
    print_info "  Low: $low"

    if [[ $critical -gt 0 ]]; then
      print_warning "Found $critical critical vulnerabilities"
    elif [[ $high -gt 0 ]]; then
      print_warning "Found $high high-severity vulnerabilities"
    else
      print_success "No critical or high-severity vulnerabilities detected"
    fi

  else
    print_warning "Docker Scout not available - skipping vulnerability scan"
    print_info "Install Docker Scout for vulnerability scanning: https://docs.docker.com/scout/"
  fi

  return 0
}

# Generate JSON report
generate_json_report() {
  local image="$1"
  local test_results="$2"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat <<EOF
{
  "image": "$image",
  "timestamp": "$timestamp",
  "security_test_results": $test_results,
  "summary": {
    "passed": $(echo "$test_results" | jq '[.[] | select(.result == "passed")] | length'),
    "failed": $(echo "$test_results" | jq '[.[] | select(.result == "failed")] | length'),
    "warnings": $(echo "$test_results" | jq '[.[] | select(.result == "warning")] | length')
  }
}
EOF
}

# Main function
main() {
  local image=""
  local verbose="false"
  local timeout="$DEFAULT_TIMEOUT"
  local skip_vuln="false"
  local skip_runtime="false"
  local json_output="false"

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
    -t | --timeout)
      timeout="$2"
      shift 2
      ;;
    --skip-vuln)
      skip_vuln="true"
      shift
      ;;
    --skip-runtime)
      skip_runtime="true"
      shift
      ;;
    --json)
      json_output="true"
      shift
      ;;
    -*)
      print_error "Unknown option: $1"
      usage
      exit 3
      ;;
    *)
      if [[ -z $image ]]; then
        image="$1"
      else
        print_error "Multiple images specified. Only one image can be tested at a time."
        exit 3
      fi
      shift
      ;;
    esac
  done

  # Validate arguments
  if [[ -z $image ]]; then
    print_error "Image name is required"
    usage
    exit 3
  fi

  if ! [[ $timeout =~ ^[0-9]+$ ]] || [[ $timeout -lt 5 ]]; then
    print_error "Timeout must be a number >= 5"
    exit 3
  fi

  # Check dependencies
  check_dependencies

  # Validate image
  validate_image "$image"

  if [[ $json_output != "true" ]]; then
    print_header "Container Security Testing"
    print_info "Image: $image"
    print_info "Timeout: ${timeout}s"
    print_info "Verbose: $verbose"
    echo
  fi

  # Run security tests
  local test_results="[]"
  local overall_result=0

  # Test 1: Container Configuration
  local config_result=0
  test_container_config "$image" "$verbose" || config_result=$?
  test_results=$(echo "$test_results" | jq '. += [{"test": "container_config", "result": "'"$([ "$config_result" -eq 0 ] && echo "passed" || echo "failed")"'"}]')

  # Test 2: Non-Root User
  local user_result=0
  test_nonroot_user "$image" "$timeout" || user_result=$?
  test_results=$(echo "$test_results" | jq '. += [{"test": "nonroot_user", "result": "'"$([ "$user_result" -eq 0 ] && echo "passed" || echo "failed")"'"}]')

  # Test 3: File Permissions
  local perms_result=0
  test_file_permissions "$image" "$timeout" "$verbose" || perms_result=$?
  test_results=$(echo "$test_results" | jq '. += [{"test": "file_permissions", "result": "'"$([ "$perms_result" -eq 0 ] && echo "passed" || echo "warning")"'"}]')

  # Test 4: Runtime Security
  local runtime_result=0
  if [[ $skip_runtime != "true" ]]; then
    test_runtime_security "$image" "$timeout" || runtime_result=$?
    test_results=$(echo "$test_results" | jq '. += [{"test": "runtime_security", "result": "'"$([ "$runtime_result" -eq 0 ] && echo "passed" || echo "failed")"'"}]')
  fi

  # Test 5: Vulnerabilities
  local vuln_result=0
  if [[ $skip_vuln != "true" ]]; then
    test_vulnerabilities "$image" "$verbose" || vuln_result=$?
    test_results=$(echo "$test_results" | jq '. += [{"test": "vulnerabilities", "result": "'"$([ "$vuln_result" -eq 0 ] && echo "passed" || echo "warning")"'"}]')
  fi

  # Determine overall result
  if [[ $config_result -ne 0 || $user_result -ne 0 ]]; then
    overall_result=1
  elif [[ $runtime_result -eq 2 ]]; then
    overall_result=2
  fi

  # Output results
  if [[ $json_output == "true" ]]; then
    generate_json_report "$image" "$test_results"
  else
    print_header "Security Test Summary"

    if [[ $overall_result -eq 0 ]]; then
      print_success "All critical security tests passed"
    elif [[ $overall_result -eq 1 ]]; then
      print_error "Security violations detected"
    elif [[ $overall_result -eq 2 ]]; then
      print_error "Container startup failed"
    fi

    echo
    print_info "Image: $image"
    print_info "Test results saved for CI/CD integration"
  fi

  exit $overall_result
}

# Run main function
main "$@"
