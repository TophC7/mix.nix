#!/usr/bin/env fish

# Update script for proton-cachyos versions
# Updates both v3 and v4 variants to the latest release

set -l scriptDir (dirname (status filename))
set -l variants v3 v4

# Check dependencies
for cmd in curl jq nix-prefetch-url nix-hash
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

# Fetch latest release tag
echo "Fetching latest release..."
set -l latestTag (curl -s 'https://api.github.com/repos/CachyOS/proton-cachyos/releases/latest' | jq -r '.tag_name')

if test -z "$latestTag" -o "$latestTag" = null
    echo "Error: Could not fetch latest release tag"
    exit 1
end

echo "Latest tag: $latestTag"

# Parse the tag format: cachyos-X.Y-Z-slr
set -l tagParts (string replace 'cachyos-' '' $latestTag | string replace -- '-slr' '' | string split '-')

if test (count $tagParts) -ne 2
    echo "Error: Unexpected tag format: $latestTag"
    echo "Expected format: cachyos-X.Y-Z-slr"
    exit 1
end

set -l latestBase $tagParts[1]
set -l latestRelease $tagParts[2]

echo "Latest version: $latestBase-$latestRelease"
echo ""

# Update each variant
set -l updated 0

for variant in $variants
    set -l versionsFile "$scriptDir/versions-$variant.json"

    if not test -f $versionsFile
        echo "Warning: $versionsFile not found, skipping"
        continue
    end

    set -l currentBase (jq -r .base < $versionsFile)
    set -l currentRelease (jq -r .release < $versionsFile)

    echo "[$variant] Current: $currentBase-$currentRelease"

    if test "$currentBase" = "$latestBase" -a "$currentRelease" = "$latestRelease"
        echo "[$variant] Already up to date"
        continue
    end

    # Construct download URL and fetch hash
    set -l fileName "proton-cachyos-$latestBase-$latestRelease-slr-x86_64_$variant.tar.xz"
    set -l downloadUrl "https://github.com/CachyOS/proton-cachyos/releases/download/$latestTag/$fileName"

    echo "[$variant] Fetching hash for: $fileName"
    set -l sha256 (nix-prefetch-url --type sha256 "$downloadUrl" 2>/dev/null)

    if test -z "$sha256"
        echo "[$variant] Error: Failed to download or hash the release"
        echo "[$variant] URL: $downloadUrl"
        continue
    end

    # Convert to SRI hash format
    set -l sriHash (nix-hash --to-sri --type sha256 $sha256)

    # Update the JSON file
    jq -n \
        --arg base "$latestBase" \
        --arg release "$latestRelease" \
        --arg hash "$sriHash" \
        '{base: $base, release: $release, hash: $hash}' >$versionsFile

    echo "[$variant] Updated: $currentBase-$currentRelease -> $latestBase-$latestRelease"
    set updated (math $updated + 1)
end

echo ""
if test $updated -gt 0
    echo "Updated $updated variant(s)"
    echo ""
    echo "Commit with:"
    echo "  git add packages/proton-cachyos/versions-*.json"
    echo "  git commit -m \"proton-cachyos: update to $latestBase.$latestRelease\""
else
    echo "All variants up to date"
end
