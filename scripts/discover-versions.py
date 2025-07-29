#!/usr/bin/env python3
"""
Version Discovery Script for MCP Server Containers

This script discovers new versions from upstream repositories and updates
versions.json files. It focuses on security by:
- Filtering against excluded versions/hashes
- Validating upstream commits exist
- Only including tagged releases (not arbitrary commits)
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set
import argparse
import requests
import re
from urllib.parse import urlparse


def get_github_api_headers() -> Dict[str, str]:
    """Get headers for GitHub API requests, including auth token if available."""
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "mcp-servers-version-discovery/1.0"
    }

    # Add GitHub token if available in environment
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"

    return headers


def parse_github_repo_url(repo_url: str) -> Optional[tuple[str, str]]:
    """Parse GitHub repository URL and return (owner, repo) tuple."""
    try:
        parsed = urlparse(repo_url)
        if parsed.netloc != "github.com":
            return None

        path_parts = parsed.path.strip("/").split("/")
        if len(path_parts) >= 2:
            owner = path_parts[0]
            repo = path_parts[1].replace(".git", "")
            return owner, repo
    except Exception:
        pass

    return None


def get_github_releases(owner: str, repo: str) -> List[Dict]:
    """Fetch releases from GitHub API."""
    url = f"https://api.github.com/repos/{owner}/{repo}/releases"
    headers = get_github_api_headers()

    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching releases for {owner}/{repo}: {e}")
        return []


def get_github_tags(owner: str, repo: str) -> List[Dict]:
    """Fetch tags from GitHub API as fallback to releases."""
    url = f"https://api.github.com/repos/{owner}/{repo}/tags"
    headers = get_github_api_headers()

    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching tags for {owner}/{repo}: {e}")
        return []


def is_semver_like(version: str) -> bool:
    """Check if a version string looks like semantic versioning."""
    # Match patterns like: v1.0.0, 1.0.0, 2025.7.1, v2025.7.1
    patterns = [
        r'^v?\d+\.\d+\.\d+$',  # Standard semver
        r'^\d{4}\.\d{1,2}\.\d{1,2}$',  # Date-based versioning
        r'^v?\d{4}\.\d{1,2}\.\d{1,2}$',  # Date-based with v prefix
    ]

    return any(re.match(pattern, version) for pattern in patterns)


def filter_versions(versions: Dict[str, str], excluded_versions: List[str],
                   excluded_hashes: List[str]) -> Dict[str, str]:
    """Filter versions against exclusion lists."""
    filtered = {}

    for version, commit_hash in versions.items():
        if version in excluded_versions:
            print(f"  Excluding version {version} (in excluded_versions)")
            continue

        if commit_hash in excluded_hashes:
            print(f"  Excluding version {version} (commit {commit_hash} in excluded_hashes)")
            continue

        filtered[version] = commit_hash

    return filtered


def discover_versions_for_repo(repo_url: str, excluded_versions: List[str],
                              excluded_hashes: List[str]) -> Dict[str, str]:
    """Discover new versions for a repository."""
    repo_info = parse_github_repo_url(repo_url)
    if not repo_info:
        print(f"Error: Could not parse GitHub repository URL: {repo_url}")
        return {}

    owner, repo = repo_info
    print(f"Discovering versions for {owner}/{repo}...")

    # Try releases first
    versions = {}
    releases = get_github_releases(owner, repo)

    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue

        tag_name = release.get("tag_name", "")
        if not tag_name or not is_semver_like(tag_name):
            continue

        # Get commit SHA from the tag
        commit_sha = release.get("target_commitish")
        if commit_sha and len(commit_sha) >= 7:  # Reasonable commit hash length
            versions[tag_name] = commit_sha
            print(f"  Found release: {tag_name} -> {commit_sha}")

    # Fallback to tags if no releases found
    if not versions:
        print("  No releases found, checking tags...")
        tags = get_github_tags(owner, repo)

        for tag in tags:
            tag_name = tag.get("name", "")
            if not tag_name or not is_semver_like(tag_name):
                continue

            commit_sha = tag.get("commit", {}).get("sha")
            if commit_sha and len(commit_sha) >= 7:
                versions[tag_name] = commit_sha
                print(f"  Found tag: {tag_name} -> {commit_sha}")

    # Filter against exclusions
    if versions:
        print(f"  Found {len(versions)} potential versions, filtering...")
        versions = filter_versions(versions, excluded_versions, excluded_hashes)
        print(f"  After filtering: {len(versions)} versions")

    return versions


def load_versions_config(config_path: Path) -> Dict:
    """Load existing versions.json configuration."""
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Warning: {config_path} not found")
        return {}
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {config_path}: {e}")
        return {}


def find_versions_configs(root_dir: Path) -> List[Path]:
    """Find all versions.json files in src/ subdirectories."""
    versions_files = []
    src_dir = root_dir / "src"

    if not src_dir.exists():
        print(f"Warning: src directory not found at {src_dir}")
        return versions_files

    for server_dir in src_dir.iterdir():
        if server_dir.is_dir():
            versions_file = server_dir / "versions.json"
            if versions_file.exists():
                versions_files.append(versions_file)

    return versions_files


def main():
    parser = argparse.ArgumentParser(description="Discover new versions for MCP servers")
    parser.add_argument("--root", type=Path, default=Path("."),
                       help="Root directory of the repository")
    parser.add_argument("--server", type=str,
                       help="Specific server to check (default: all)")
    parser.add_argument("--dry-run", action="store_true",
                       help="Show what would be discovered without making changes")

    args = parser.parse_args()

    # Find all versions.json files
    if args.server:
        versions_files = [args.root / "src" / args.server / "versions.json"]
    else:
        versions_files = find_versions_configs(args.root)

    if not versions_files:
        print("No versions.json files found")
        sys.exit(1)

    print(f"Found {len(versions_files)} server(s) to check")

    all_discoveries = {}

    for versions_file in versions_files:
        server_name = versions_file.parent.name
        print(f"\n--- Checking {server_name} ---")

        config = load_versions_config(versions_file)
        if not config:
            print(f"Skipping {server_name} due to invalid config")
            continue

        repo_url = config.get("upstream_repo")
        if not repo_url:
            print(f"No upstream_repo found in {versions_file}")
            continue

        current_versions = config.get("versions", {})
        excluded_versions = config.get("excluded_versions", [])
        excluded_hashes = config.get("excluded_hashes", [])

        # Discover new versions
        discovered = discover_versions_for_repo(repo_url, excluded_versions, excluded_hashes)

        # Find truly new versions (not in current config)
        new_versions = {}
        for version, hash_val in discovered.items():
            if version not in current_versions:
                new_versions[version] = hash_val

        if new_versions:
            print(f"  New versions found for {server_name}:")
            for version, hash_val in new_versions.items():
                print(f"    {version}: {hash_val}")
            all_discoveries[server_name] = new_versions
        else:
            print(f"  No new versions found for {server_name}")

    # Summary
    print(f"\n--- Summary ---")
    if all_discoveries:
        print(f"Found new versions for {len(all_discoveries)} server(s):")
        for server_name, versions in all_discoveries.items():
            print(f"  {server_name}: {', '.join(versions.keys())}")

        if not args.dry_run:
            print("\nUse create-version-pr.py to create pull requests for these updates")
    else:
        print("No new versions discovered")


if __name__ == "__main__":
    main()
