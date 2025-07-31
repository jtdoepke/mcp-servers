# MCP Server Container Build and Test Makefile
#
# This Makefile provides targets for building, testing, and validating
# all MCP server containers with comprehensive security checks.

.PHONY: help build test clean security-test list validate-all build-all
.DEFAULT_GOAL := help

# Configuration
REGISTRY_PREFIX ?= ghcr.io/jtdoepke/mcp-servers
SCRIPT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/scripts
BUILD_DATE := $(shell date -u +"%Y%m%d")

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Helper functions
define print_header
	@printf "\n${BLUE}=== $(1) ===${NC}\n"
endef

define print_success
	@printf "${GREEN}✅ $(1)${NC}\n"
endef

define print_error
	@printf "${RED}❌ $(1)${NC}\n"
endef

define print_info
	@printf "${BLUE}ℹ️  $(1)${NC}\n"
endef

# Discover all MCP servers from src/ directories
SERVERS := $(notdir $(wildcard src/*))
SERVER_DIRS := $(wildcard src/*)

help: ## Show this help message
	@echo "MCP Server Container Build System"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${BLUE}%-20s${NC} %s\n", $$1, $$2}'
	@echo ""
	@echo "Available servers: $(SERVERS)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                          # Build all servers"
	@echo "  make build SERVER=sequentialthinking # Build specific server"
	@echo "  make test                           # Test all built containers"
	@echo "  make test SERVER=sequentialthinking  # Test specific server"
	@echo "  make clean                          # Remove all built containers"
	@echo "  make clean SERVER=sequentialthinking # Clean specific server"
	@echo "  make security-test                  # Run security validation on all containers"

list: ## List all discovered MCP servers and their versions
	$(call print_header,Discovered MCP Servers)
	@for server_dir in $(SERVER_DIRS); do \
		server=$$(basename $$server_dir); \
		if [ -f "$$server_dir/versions.json" ]; then \
			printf "${BLUE}Server: $$server${NC}\n"; \
			versions=$$(jq -r '.versions | keys[]' "$$server_dir/versions.json" 2>/dev/null || echo "none"); \
			if [ "$$versions" != "none" ]; then \
				printf "  Versions: "; echo "$$versions" | tr '\n' ' '; echo; \
			else \
				echo "  No versions configured"; \
			fi; \
			upstream=$$(jq -r '.upstream_repo // "unknown"' "$$server_dir/versions.json" 2>/dev/null); \
			echo "  Upstream: $$upstream"; \
			echo; \
		else \
			printf "${YELLOW}Server: $$server (no versions.json)${NC}\n"; \
		fi; \
	done

validate-deps: ## Check for required dependencies
	$(call print_header,Checking Dependencies)
	@command -v docker >/dev/null 2>&1 || ($(call print_error,Docker is required) && exit 1)
	@command -v jq >/dev/null 2>&1 || ($(call print_error,jq is required) && exit 1)
	@command -v pre-commit >/dev/null 2>&1 || ($(call print_error,pre-commit is required) && exit 1)
	$(call print_success,All dependencies available)

# Build function for servers
define build_server
	$(call print_header,Building $(1) Server)
	@if [ ! -f "src/$(1)/versions.json" ]; then \
		$(call print_error,No versions.json found for $(1)); \
		exit 1; \
	fi
	@if [ ! -f "src/$(1)/Dockerfile" ]; then \
		$(call print_error,No Dockerfile found for $(1)); \
		exit 1; \
	fi
	@set -e; \
	upstream_repo=$$(jq -r '.upstream_repo' "src/$(1)/versions.json"); \
	echo "$$upstream_repo" > /tmp/upstream_repo_$(1); \
	jq -r '.versions | to_entries[] | "\(.key) \(.value)"' "src/$(1)/versions.json" | \
	while IFS=' ' read -r version commit_hash; do \
		upstream_repo=$$(cat /tmp/upstream_repo_$(1)); \
		image_name="$(1):$$version"; \
		printf "${BLUE}ℹ️  Building $$image_name with commit $$commit_hash${NC}\n"; \
		if docker build \
			--build-arg SRC_REPO="$$upstream_repo" \
			--build-arg SRC_HASH="$$commit_hash" \
			-t "$$image_name" \
			"src/$(1)/"; then \
			printf "${GREEN}✅ Built $$image_name${NC}\n"; \
			docker tag "$$image_name" "$(1):latest"; \
		else \
			printf "${RED}❌ Failed to build $$image_name${NC}\n"; \
			rm -f /tmp/upstream_repo_$(1); \
			exit 1; \
		fi; \
	done; \
	rm -f /tmp/upstream_repo_$(1)
endef

# Main build target - can build all servers or specific server
build: validate-deps ## Build containers (usage: make build [SERVER=server_name])
ifdef SERVER
	@if [ ! -d "src/$(SERVER)" ]; then \
		$(call print_error,Server $(SERVER) not found); \
		$(call print_info,Available servers: $(SERVERS)); \
		exit 1; \
	fi
	@$(call build_server,$(SERVER))
	$(call print_success,Server $(SERVER) built successfully)
else
	$(call print_header,Building All MCP Servers)
	@for server in $(SERVERS); do \
		$(MAKE) --no-print-directory build SERVER=$$server; \
	done
	$(call print_success,All servers built successfully)
endif

# Test function for servers
test_server = \
	$(call print_header,Testing $(1) Server); \
	if [ ! -f "$(SCRIPT_DIR)/test-container-security.sh" ]; then \
		$(call print_error,Security test script not found); \
		exit 1; \
	fi; \
	jq -r '.versions | keys[]' "src/$(1)/versions.json" 2>/dev/null | \
	while IFS= read -r version; do \
		image_name="$(1):$$version"; \
		if docker inspect "$$image_name" >/dev/null 2>&1; then \
			$(call print_info,Testing $$image_name); \
			if "$(SCRIPT_DIR)/test-container-security.sh" "$$image_name"; then \
				$(call print_success,$$image_name passed security tests); \
			else \
				$(call print_error,$$image_name failed security tests); \
				exit 1; \
			fi; \
		else \
			$(call print_error,Image $$image_name not found - build it first); \
			exit 1; \
		fi; \
	done

# Main test target - can test all servers or specific server
test: ## Test containers (usage: make test [SERVER=server_name])
ifdef SERVER
	@if [ ! -d "src/$(SERVER)" ]; then \
		$(call print_error,Server $(SERVER) not found); \
		$(call print_info,Available servers: $(SERVERS)); \
		exit 1; \
	fi
	@$(call test_server,$(SERVER))
	$(call print_success,Server $(SERVER) passed all tests)
else
	$(call print_header,Testing All MCP Servers)
	@for server in $(SERVERS); do \
		$(MAKE) --no-print-directory test SERVER=$$server; \
	done
	$(call print_success,All servers passed security tests)
endif

# Clean function for servers
clean_server = \
	$(call print_header,Cleaning $(1) Server Images); \
	jq -r '.versions | keys[]' "src/$(1)/versions.json" 2>/dev/null | \
	while IFS= read -r version; do \
		image_name="$(1):$$version"; \
		if docker inspect "$$image_name" >/dev/null 2>&1; then \
			docker rmi "$$image_name" 2>/dev/null || true; \
			$(call print_info,Removed $$image_name); \
		fi; \
	done; \
	docker rmi "$(1):latest" 2>/dev/null || true

# Main clean target - can clean all servers or specific server
clean: ## Remove containers (usage: make clean [SERVER=server_name])
ifdef SERVER
	@if [ ! -d "src/$(SERVER)" ]; then \
		$(call print_error,Server $(SERVER) not found); \
		$(call print_info,Available servers: $(SERVERS)); \
		exit 1; \
	fi
	@$(call clean_server,$(SERVER))
	$(call print_success,Server $(SERVER) images cleaned)
else
	$(call print_header,Cleaning All MCP Server Images)
	@for server in $(SERVERS); do \
		$(MAKE) --no-print-directory clean SERVER=$$server; \
	done
	$(call print_info,Cleaning up dangling images)
	@docker image prune -f >/dev/null 2>&1 || true
	$(call print_success,All containers cleaned)
endif

security-test: validate-deps ## Run comprehensive security validation on all containers
	$(call print_header,Comprehensive Security Validation)
	@if [ ! -f "$(SCRIPT_DIR)/validate-all-containers.sh" ]; then \
		$(call print_error,Validation script not found); \
		exit 1; \
	fi
	@"$(SCRIPT_DIR)/validate-all-containers.sh" --local --verbose
	$(call print_success,Security validation completed)

pre-commit-test: ## Run pre-commit hooks on all files
	$(call print_header,Running Pre-commit Validation)
	@pre-commit run --all-files
	$(call print_success,Pre-commit validation passed)

registry-build: validate-deps ## Build containers with registry tags for publishing
	$(call print_header,"Building Registry-Tagged Images")
	@for server_dir in $(SERVER_DIRS); do \
		server=$$(basename $$server_dir); \
		if [ -f "$$server_dir/versions.json" ]; then \
			upstream_repo=$$(jq -r '.upstream_repo' "$$server_dir/versions.json"); \
			jq -r '.versions | to_entries[] | "\(.key) \(.value)"' "$$server_dir/versions.json" | \
			while IFS=' ' read -r version commit_hash; do \
				local_name="$$server:$$version"; \
				registry_name="$(REGISTRY_PREFIX):$$server-$$version"; \
				dated_name="$(REGISTRY_PREFIX):$$server-$$version-$(BUILD_DATE)"; \
				$(call print_info,"Building $$registry_name"); \
				if docker build \
					--build-arg SRC_REPO="$$upstream_repo" \
					--build-arg SRC_HASH="$$commit_hash" \
					-t "$$local_name" \
					-t "$$registry_name" \
					-t "$$dated_name" \
					"$$server_dir/" 2>&1; then \
					$(call print_success,"Built $$registry_name"); \
				else \
					$(call print_error,"Failed to build $$registry_name"); \
					exit 1; \
				fi; \
			done; \
			docker tag "$$server:latest" "$(REGISTRY_PREFIX):$$server" 2>/dev/null || true; \
		fi; \
	done
	$(call print_success,"Registry-tagged images built")

validate: pre-commit-test build-all test-all security-test ## Run full validation pipeline
	$(call print_success,"Full validation pipeline completed successfully")

stats: ## Show build statistics and container information
	$(call print_header,"Container Build Statistics")
	@echo "Servers discovered: $(words $(SERVERS))"
	@echo "Servers: $(SERVERS)"
	@echo ""
	@echo "Local images:"
	@docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep -E "($(subst $(space),|,$(SERVERS)))" || echo "No images built yet"
	@echo ""
	@echo "Registry prefix: $(REGISTRY_PREFIX)"
	@echo "Build date: $(BUILD_DATE)"

# Development targets
dev-build: validate-deps ## Quick build without full validation (development only)
	$(call print_header,"Development Build")
	@echo "⚠️  This is a development build - skipping comprehensive validation"
	@$(MAKE) --no-print-directory build-all
	$(call print_success,"Development build completed")

dev-test: ## Quick test of first available container (development only)
	$(call print_header,"Development Test")
	@echo "⚠️  This is a quick test - use 'make test' for full validation"
	@first_server=$$(echo $(SERVERS) | cut -d' ' -f1); \
	if [ -n "$$first_server" ]; then \
		$(MAKE) --no-print-directory test-$$first_server; \
	else \
		$(call print_error,"No servers found"); \
	fi

# Maintenance targets
update-versions: ## Check for new versions (requires scripts)
	$(call print_header,"Checking for Version Updates")
	@if [ -f "$(SCRIPT_DIR)/discover-versions.py" ]; then \
		python3 "$(SCRIPT_DIR)/discover-versions.py"; \
	else \
		$(call print_error,"Version discovery script not found"); \
	fi

inspect-%: ## Inspect a specific container (usage: make inspect-sequentialthinking)
	$(call print_header,"Inspecting $* Container")
	@if docker inspect "$*:latest" >/dev/null 2>&1; then \
		echo "Image: $*:latest"; \
		echo "User: $$(docker inspect $*:latest --format='{{.Config.User}}')"; \
		echo "Entrypoint: $$(docker inspect $*:latest --format='{{.Config.Entrypoint}}')"; \
		echo "Cmd: $$(docker inspect $*:latest --format='{{.Config.Cmd}}')"; \
		echo "WorkingDir: $$(docker inspect $*:latest --format='{{.Config.WorkingDir}}')"; \
		echo "Size: $$(docker images $*:latest --format '{{.Size}}')"; \
	else \
		$(call print_error,"Container $*:latest not found - build it first"); \
	fi
