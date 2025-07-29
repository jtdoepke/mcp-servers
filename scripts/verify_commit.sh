#!/usr/bin/env bash

# Usage message
if [ $# -ne 2 ]; then
	echo "Usage: $0 <owner/repo> <commit-sha>"
	echo "  Verfiy a commit's signature is valid according to GitHub."
	echo "  Example: $0 torvalds/linux abc1234"
	exit 1
fi

REPO="$1"
COMMIT_SHA="$2"

# GitHub API endpoint
API_URL="https://api.github.com/repos/$REPO/commits/$COMMIT_SHA"

# Fetch commit data from GitHub
echo "Fetching commit $COMMIT_SHA from $REPO..."
RESPONSE=$(curl -s -H "Accept: application/vnd.github+json" "$API_URL")

# Check if commit was found
if echo "$RESPONSE" | grep -q '"message": "Not Found"'; then
	echo "❌ Commit not found in repository $REPO."
	exit 1
fi

# Extract verification status
VERIFIED=$(echo "$RESPONSE" | jq -r '.commit.verification.verified')
REASON=$(echo "$RESPONSE" | jq -r '.commit.verification.reason')
SIGNATURE=$(echo "$RESPONSE" | jq -r '.commit.verification.signature')
PAYLOAD=$(echo "$RESPONSE" | jq -r '.commit.verification.payload')

# Output verification result
if [ "$VERIFIED" == "true" ]; then
	echo "✅ GitHub verified the signature on this commit."
	echo "Reason: $REASON"
else
	echo "❌ GitHub could not verify the signature on this commit."
	echo "Reason: $REASON"
fi

# Optionally show the raw signature if present
if [ "$SIGNATURE" != "null" ]; then
	echo ""
	echo "Signature:"
	echo "$SIGNATURE"
fi

# Optionally show the payload if present
if [ "$PAYLOAD" != "null" ]; then
	echo ""
	echo "Payload:"
	echo "$PAYLOAD"
fi
