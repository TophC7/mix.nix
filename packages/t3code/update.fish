#!/usr/bin/env fish

# Update script for t3code
#
# Fetches the latest commit from pingdotgg/t3code main, re-hashes the source
# and BOTH bun dep FoDs (buildtime + runtime), and writes the new values to
# version.json.
#
# Hash discovery: we sentinel both depsHash and runtimeDepsHash, then run
# `nix build --keep-going`. Because the two FoDs are independent derivations,
# nix attempts them concurrently and both fail with "hash mismatch" errors.
# A tiny awk filter walks the error stream, tracks which derivation each
# error block belongs to by scanning for its drv name, and emits the real
# "got:" hashes keyed by purpose (build/runtime).

set -l scriptDir (dirname (status filename))
set -l versionFile "$scriptDir/version.json"

# Check dependencies
for cmd in curl jq nix-prefetch-git nix awk
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

# ── Sentinel write + dual-hash discovery ─────────────────────────────────────

set -l latestVersion "unstable-$latestDate-$shortRev"
set -l fakeHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

echo "Writing sentinel version.json to trigger hash discovery..."
jq -n \
    --arg version "$latestVersion" \
    --arg rev "$latestRev" \
    --arg hash "$latestHash" \
    --arg depsHash "$fakeHash" \
    --arg runtimeDepsHash "$fakeHash" \
    '{version: $version, rev: $rev, hash: $hash, depsHash: $depsHash, runtimeDepsHash: $runtimeDepsHash}' >$versionFile

set -l flakeRoot (git -C $scriptDir rev-parse --show-toplevel)

echo "Running nix build --keep-going to discover both FoD hashes..."
set -l buildOutput (nix build --keep-going --no-link "$flakeRoot#t3code" 2>&1)

# Walk the error stream. "hash mismatch in fixed-output derivation" lines
# name the drv; the following "got:" line has the real hash. Tag each
# captured hash with "build" or "runtime" based on whether the drv name
# contains "-bun-deps-runtime-" or just "-bun-deps-".
#
# `string join \n` preserves newlines between list elements -- fish split
# the nix output into per-line list elements during capture, and piping
# via `echo` would re-join them with spaces and defeat awk's per-line
# regex matching.
set -l parsed (string join \n -- $buildOutput | awk '
    /hash mismatch in fixed-output derivation/ {
        if ($0 ~ /t3code-bun-deps-runtime-/) {
            current = "runtime"
        } else if ($0 ~ /t3code-bun-deps-/) {
            current = "build"
        } else {
            current = ""
        }
        next
    }
    /got:[ \t]+sha256-/ && current != "" {
        match($0, /sha256-[A-Za-z0-9+\/=]+/)
        print current "=" substr($0, RSTART, RLENGTH)
        current = ""
    }
')

set -l newDepsHash ""
set -l newRuntimeDepsHash ""
for line in $parsed
    switch $line
        case 'build=*'
            set newDepsHash (string replace 'build=' '' -- $line)
        case 'runtime=*'
            set newRuntimeDepsHash (string replace 'runtime=' '' -- $line)
    end
end

if test -z "$newDepsHash" -o -z "$newRuntimeDepsHash"
    echo "Error: Could not extract both hashes from build output."
    echo "  depsHash:        $newDepsHash"
    echo "  runtimeDepsHash: $newRuntimeDepsHash"
    echo ""
    echo "Full output:"
    echo $buildOutput
    echo ""
    echo "Reverting version.json"
    git -C $flakeRoot checkout -- $versionFile
    exit 1
end

echo "New depsHash:        $newDepsHash"
echo "New runtimeDepsHash: $newRuntimeDepsHash"

# ── Write final version.json ─────────────────────────────────────────────────

jq -n \
    --arg version "$latestVersion" \
    --arg rev "$latestRev" \
    --arg hash "$latestHash" \
    --arg depsHash "$newDepsHash" \
    --arg runtimeDepsHash "$newRuntimeDepsHash" \
    '{version: $version, rev: $rev, hash: $hash, depsHash: $depsHash, runtimeDepsHash: $runtimeDepsHash}' >$versionFile

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
