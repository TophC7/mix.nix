#!/usr/bin/env fish

# Update script for bb
# Pins the latest desktop-v* release's x86_64 AppImage in version.json

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

# The repo also publishes rolling desktop-latest/desktop-nightly tags; only versioned tags pin.
set -l latestTag (curl -s 'https://api.github.com/repos/get-bb/bb/releases?per_page=20' \
    | jq -r '[.[] | select(.prerelease | not) | .tag_name | select(test("^desktop-v"))][0] // empty')
if test -z "$latestTag"
    echo "Error: Could not fetch latest release"
    exit 1
end
set -l latestVersion (string replace -r '^desktop-v' '' $latestTag)

if test "$latestVersion" = "$currentVersion"
    echo "Already up to date"
    exit 0
end

set -l url "https://github.com/get-bb/bb/releases/download/$latestTag/bb-$latestVersion-x86_64.AppImage"
echo "Prefetching $url"
set -l sha256 (nix-prefetch-url --type sha256 $url 2>/dev/null)
if test -z "$sha256"
    echo "Error: Failed to fetch AppImage"
    exit 1
end
set -l sriHash (nix hash convert --hash-algo sha256 --to sri $sha256)

jq -n --arg version $latestVersion --arg hash $sriHash \
    '{version: $version, hash: $hash}' >$versionFile

echo "Updated: $currentVersion -> $latestVersion"
echo ""
echo "Commit with:"
echo "  git add packages/bb/version.json"
echo "  git commit -m \"bb: update to $latestVersion\""
