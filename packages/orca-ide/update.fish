#!/usr/bin/env fish

# Update script for orca-ide
# Pins the latest GitHub release's Linux .debs in version.json

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

# The repo also publishes mobile prereleases; releases/latest is the desktop app.
set -l latestTag (curl -s https://api.github.com/repos/stablyai/orca/releases/latest | jq -r '.tag_name // empty')
if test -z "$latestTag"
    echo "Error: Could not fetch latest release"
    exit 1
end
set -l latestVersion (string replace -r '^v' '' $latestTag)

if test "$latestVersion" = "$currentVersion"
    echo "Already up to date"
    exit 0
end

set -l hashes '{}'
for pair in x86_64-linux:amd64 aarch64-linux:arm64
    set -l system (string split : $pair)[1]
    set -l arch (string split : $pair)[2]
    set -l url "https://github.com/stablyai/orca/releases/download/$latestTag/orca-ide_"$latestVersion"_$arch.deb"
    echo "Prefetching $url"
    set -l sha256 (nix-prefetch-url --type sha256 $url 2>/dev/null)
    if test -z "$sha256"
        echo "Error: Failed to fetch $url"
        exit 1
    end
    set hashes (echo $hashes | jq --arg s $system --arg h (nix hash convert --hash-algo sha256 --to sri $sha256) '. + {($s): $h}')
end

jq -n --arg version $latestVersion --argjson hashes $hashes \
    '{version: $version, hashes: $hashes}' >$versionFile

echo "Updated: $currentVersion -> $latestVersion"
echo ""
echo "Commit with:"
echo "  git add packages/orca-ide/version.json"
echo "  git commit -m \"orca-ide: update to $latestVersion\""
