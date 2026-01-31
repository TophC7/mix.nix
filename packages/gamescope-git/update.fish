#!/usr/bin/env fish

# Update script for gamescope-git
# Fetches the latest commit from master and updates version.json

set -l scriptDir (dirname (status filename))
set -l versionFile "$scriptDir/version.json"

# Check dependencies
for cmd in curl jq nix-prefetch-git
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

# Read current version
set -l currentRev (jq -r .rev < $versionFile)
echo "Current rev: $currentRev"

echo "Fetching latest from ValveSoftware/gamescope master..."

# Fetch latest commit info
set -l prefetchOutput (nix-prefetch-git --quiet --fetch-submodules https://github.com/ValveSoftware/gamescope.git 2>&1)

if test $status -ne 0
    echo "Error: Failed to prefetch repository"
    echo $prefetchOutput
    exit 1
end

set -l latestRev (echo $prefetchOutput | jq -r .rev)
set -l latestHash (echo $prefetchOutput | jq -r .hash)
set -l latestDate (echo $prefetchOutput | jq -r .date | string replace -a '-' '' | string replace -a ':' '' | string replace 'T' '' | string sub -l 14)
set -l shortRev (string sub -l 7 $latestRev)

if test -z "$latestRev" -o "$latestRev" = null
    echo "Error: Could not parse prefetch output"
    exit 1
end

echo "Latest rev: $latestRev"

if test "$currentRev" = "$latestRev"
    echo "Already up to date"
    exit 0
end

# Format version string
set -l latestVersion "unstable-$latestDate-$shortRev"

# Update the JSON file
jq -n \
    --arg version "$latestVersion" \
    --arg rev "$latestRev" \
    --arg hash "$latestHash" \
    '{version: $version, rev: $rev, hash: $hash}' >$versionFile

echo "Updated: $currentRev -> $latestRev"
echo "Version: $latestVersion"
echo ""
echo "Commit with:"
echo "  git add packages/gamescope-git/version.json"
echo "  git commit -m \"gamescope-git: update to $latestVersion\""
