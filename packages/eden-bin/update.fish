#!/usr/bin/env fish

# Update script for eden-bin
# Pins the latest Eden release's amd64 PGO AppImage in version.json

set -l scriptDir (dirname (status filename))
set -l versionFile "$scriptDir/version.json"

for cmd in curl jq nix-prefetch-url nix
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

set -l currentVersion (jq -r .version <$versionFile)
echo "Current version: $currentVersion"

set -l latestTag (curl -s 'https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases?limit=1' | jq -r '.[0].tag_name // empty')
if test -z "$latestTag"
    echo "Error: Could not fetch latest release"
    exit 1
end
set -l latestVersion (string replace -r '^v' '' $latestTag)

if test "$latestVersion" = "$currentVersion"
    echo "Already up to date"
    exit 0
end

set -l url "https://stable.eden-emu.dev/v$latestVersion/Eden-Linux-v$latestVersion-amd64-clang-pgo.AppImage"
echo "Prefetching $url"
set -l sha256 (nix-prefetch-url --type sha256 $url 2>/dev/null)
if test -z "$sha256"
    echo "Error: Failed to fetch AppImage"
    exit 1
end
set -l sriHash (nix hash convert --hash-algo sha256 --to sri $sha256)

jq -n --arg version "$latestVersion" --arg hash "$sriHash" \
    '{version: $version, hash: $hash}' >$versionFile

echo "Updated: $currentVersion -> $latestVersion"
echo ""
echo "Commit with:"
echo "  git add packages/eden-bin/version.json"
echo "  git commit -m \"eden-bin: update to $latestVersion\""
