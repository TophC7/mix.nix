#!/usr/bin/env fish

# Update script for t3code
#
# Fetches the latest commit from pingdotgg/t3code main, re-hashes the source
# and the bun deps FoD, and writes the new values to version.json.
#
# The deps hash discovery works by setting depsHash to a sentinel value,
# invoking nix build, and parsing the "got:" line from the resulting
# hash mismatch error.

set -l scriptDir (dirname (status filename))
set -l versionFile "$scriptDir/version.json"

# Check dependencies
for cmd in curl jq nix-prefetch-git nix
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

# ── Read current state ───────────────────────────────────────────────────────

set -l currentRev (jq -r .rev <$versionFile)
echo "Current rev: $currentRev"

# ── Fetch latest main commit ─────────────────────────────────────────────────

echo "Fetching latest from pingdotgg/t3code main..."

set -l prefetchOutput (nix-prefetch-git --quiet https://github.com/pingdotgg/t3code.git 2>&1)

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

echo "Latest rev:  $latestRev"

if test "$currentRev" = "$latestRev"
    echo "Already up to date"
    exit 0
end

# ── Discover new depsHash ────────────────────────────────────────────────────

# Format version string up front so the sentinel write mirrors the final file.
set -l latestVersion "unstable-$latestDate-$shortRev"
set -l fakeHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

echo "Writing sentinel version.json to trigger hash discovery..."
jq -n \
    --arg version "$latestVersion" \
    --arg rev "$latestRev" \
    --arg hash "$latestHash" \
    --arg depsHash "$fakeHash" \
    '{version: $version, rev: $rev, hash: $hash, depsHash: $depsHash}' >$versionFile

# Find the repo root so `nix build .#t3code` targets the right flake even
# when the script is run from a different cwd.
set -l flakeRoot (git -C $scriptDir rev-parse --show-toplevel)

echo "Running nix build to discover depsHash (expected to fail on hash mismatch)..."
set -l buildOutput (nix build --no-link "$flakeRoot#t3code" 2>&1)
set -l newDepsHash (echo $buildOutput | string match -r 'got:\s+(sha256-[A-Za-z0-9+/=]+)' | tail -n +2)

if test -z "$newDepsHash"
    echo "Error: Could not extract depsHash from build output. Full output:"
    echo $buildOutput
    echo ""
    echo "Reverting version.json"
    git -C $flakeRoot checkout -- $versionFile
    exit 1
end

echo "New depsHash: $newDepsHash"

# ── Write final version.json ─────────────────────────────────────────────────

jq -n \
    --arg version "$latestVersion" \
    --arg rev "$latestRev" \
    --arg hash "$latestHash" \
    --arg depsHash "$newDepsHash" \
    '{version: $version, rev: $rev, hash: $hash, depsHash: $depsHash}' >$versionFile

echo ""
echo "Updated: $currentRev -> $latestRev"
echo "Version: $latestVersion"

# ── Verify the build actually succeeds ───────────────────────────────────────

echo ""
echo "Verifying build..."
if nix build --no-link "$flakeRoot#t3code" >/dev/null 2>&1
    echo "Build OK"
else
    echo "Warning: verification build failed. version.json has been updated but"
    echo "t3code no longer builds. Inspect with: nix build $flakeRoot#t3code"
    exit 1
end

echo ""
echo "Commit with:"
echo "  git add packages/t3code/version.json"
echo "  git commit -m \"t3code: update to $latestVersion\""
