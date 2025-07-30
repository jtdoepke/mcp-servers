#!/usr/bin/env python3
"""Parse the output from discover-versions.py to extract structured version data."""

import json
import subprocess
import sys

def parse_discovery_output(server_name):
    """Run discovery for a specific server and parse the output."""
    # Run discovery for specific server
    result = subprocess.run(
        ['python', 'scripts/discover-versions.py', '--server', server_name],
        capture_output=True,
        text=True
    )

    # Parse the output to extract new versions
    output_lines = result.stdout.split('\n')
    new_versions = {}

    capture_versions = False
    for line in output_lines:
        if f'New versions found for {server_name}:' in line:
            capture_versions = True
            continue
        elif capture_versions and line.strip().startswith('  '):
            # Parse lines like '    v1.0.0: abc123hash'
            if ':' in line:
                version, hash_val = line.strip().split(':', 1)
                new_versions[version.strip()] = hash_val.strip()
        elif capture_versions and not line.strip().startswith('  '):
            break

    return new_versions

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(json.dumps({}))
        sys.exit(0)

    server_name = sys.argv[1]
    versions = parse_discovery_output(server_name)
    print(json.dumps(versions))
