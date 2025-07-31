# MCP Servers

> It's not that I don't trust you, but ...

A repo for building Docker containers of MCP servers because I don't trust blind `npm install -g @<MCP_SERVER>`.

## About This Repository

This repository builds Docker containers for MCP (Model Context Protocol) servers as a security-focused alternative to direct npm/pip installations. The MCP ecosystem faces significant supply chain security risks including malicious packages, typosquatting, dependency confusion attacks, and prompt injection vulnerabilities through compromised servers.

This project addresses these security concerns through:

- **Source pinning**: All servers built from specific commit hashes, preventing malicious updates
- **Container isolation**: Sandboxed execution environment isolates MCP servers from host system
- **Automated security scanning**: Daily vulnerability assessments of containers and dependencies
- **Version control**: Manual curation of approved versions with exclusion lists for problematic releases
- **Non-root execution**: All containers run as non-privileged users (UID 65532)
- **Minimal attack surface**: Distroless base images with no shell or package managers where possible

### Security Benefits Over Direct Installation

Installing MCP servers directly via `npm install -g` or `pip install` creates several attack vectors:

- **Supply chain attacks**: Malicious actors can compromise official registries with poisoned packages
- **Typosquatting**: Attackers create packages with similar names to legitimate MCP servers
- **Dependency confusion**: Mixing internal and public repositories can lead to installing malicious versions
- **Runtime modification**: Servers can be updated remotely without user knowledge or consent
- **System access**: Direct installations run with user privileges and full system access

This containerized approach eliminates these risks by providing:
- Audit trail for all included code through commit hash pinning
- Immutable deployments that prevent unauthorized modifications
- Isolated execution preventing lateral movement if compromised
- Cryptographic verification of container integrity (planned)

## MCP Servers

This repository builds and maintains Docker containers for the following MCP servers:

### sequentialthinking

**Source**: [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking)

A tool for dynamic and reflective problem-solving through structured thinking processes. Helps break down complex problems into manageable steps, revise thoughts dynamically, and branch into alternative reasoning paths.

**Docker Configuration Example**:
```json
{
  "mcpServers": {
    "sequentialthinking": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "ghcr.io/jtdoepke/mcp-servers:sequentialthinking"
      ]
    }
  }
}
```

**Environment Variables**:
- `DISABLE_THOUGHT_LOGGING` (optional): Set to `"true"` to disable logging of thought information

**Persistent State**: None required - server is stateless

**Available Tags**:
- `ghcr.io/jtdoepke/mcp-servers:sequentialthinking` (latest approved version)
- `ghcr.io/jtdoepke/mcp-servers:sequentialthinking-2025.7.1` (specific version)
- `ghcr.io/jtdoepke/mcp-servers:sequentialthinking-2025.7.1-YYYYMMDD` (dated builds for security tracking)

## TODO - Future Improvements

### Security Enhancements
- [ ] **Container signing**: Implement cosign for cryptographic verification of container integrity
- [ ] **Runtime behavior monitoring**: Anomaly detection for unusual MCP server behavior patterns
- [ ] **Network policy enforcement**: Restrict container network access to only required endpoints
- [ ] **SLSA attestation**: Generate build provenance attestations for supply chain verification
- [ ] **CVE integration**: Real-time vulnerability alerts and automated security updates
- [ ] **Secret scanning**: Enhanced detection of leaked credentials in source code and containers

### Authentication & Authorization
- [ ] **OAuth token scoping**: Fine-grained permission models limiting MCP server access rights
- [ ] **Token rotation**: Automated credential refresh mechanisms for connected services
- [ ] **Human-in-the-loop**: Approval gates for sensitive operations and high-privilege actions
- [ ] **Access logging**: Comprehensive audit trails for all MCP server interactions
- [ ] **Permission boundaries**: Sandboxing mechanisms to limit server capabilities

### Monitoring & Observability
- [ ] **OpenTelemetry integration**: Distributed tracing for MCP server execution paths
- [ ] **Performance metrics**: Resource usage monitoring and optimization recommendations
- [ ] **Health checks**: Automated monitoring of server availability and responsiveness
- [ ] **Alerting**: Notification systems for security events and operational issues

### Developer Experience
- [ ] **Multi-architecture builds**: Support for ARM64 and other architectures
- [ ] **Development containers**: Pre-configured environments for testing and development
- [ ] **Integration tests**: Automated testing of MCP server functionality in containers
- [ ] **Documentation automation**: Auto-generated docs from server configurations
