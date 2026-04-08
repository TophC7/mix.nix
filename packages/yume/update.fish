#!/usr/bin/env fish

# Update script for yume
# Fetches the latest GitHub release and updates version.json

set -l scriptDir (dirname (status filename))
set -l versionFile "$scriptDir/version.json"

# Check dependencies
for cmd in curl jq nix-prefetch-url nix-hash
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

# Read current version
set -l currentVersion (jq -r .version < $versionFile)
echo "Current version: $currentVersion"

echo "Checking for latest release..."

set -l latestRelease (curl -s https://api.github.com/repos/aofp/yume/releases/latest)
set -l latestTag (echo $latestRelease | jq -r '.tag_name // empty')

if test -z "$latestTag"
    echo "Error: Could not fetch latest release"
    exit 1
end

set -l latestVersion (string replace -r '^v' '' "$latestTag")

echo "Latest version: $latestVersion"

if test "$currentVersion" = "$latestVersion"
    echo "Already up to date"
    exit 0
end

set -l latestUrl "https://github.com/aofp/yume/releases/download/v$latestVersion/yume_{$latestVersion}_amd64.deb"

echo "Prefetching $latestUrl..."
set -l prefetchOutput (nix-prefetch-url --type sha256 "$latestUrl" 2>&1)

if test $status -ne 0
    echo "Error: Failed to prefetch release"
    echo $prefetchOutput >&2
    exit 1
end

set -l sha256 (echo $prefetchOutput | tail -1)
set -l latestHash (nix-hash --to-sri --type sha256 $sha256)

# Update version.json
jq -n \
    --arg version "$latestVersion" \
    --arg url "$latestUrl" \
    --arg hash "$latestHash" \
    '{version: $version, url: $url, hash: $hash}' >$versionFile

echo "Updated: $currentVersion -> $latestVersion"
echo ""
echo "Commit with:"
echo "  git add packages/yume/version.json"
echo "  git commit -m \"yume: $currentVersion -> $latestVersion\""
