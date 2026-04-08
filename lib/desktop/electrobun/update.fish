#!/usr/bin/env fish

# Update script for the shared Electrobun builder
#
# Refreshes lib/desktop/electrobun/version.json:
#   1. electrobun.{version,cliHash,coreHash}
#      Default: latest upstream release. Override with --electrobun=VERSION.
#   2. bunDepsHash
#      Sentineled, discovered from a nix build's hash-mismatch error.
#
# Usage:
#   ./update.fish                           # latest electrobun
#   ./update.fish --electrobun=1.17.0       # pin a specific version
#   ./update.fish --deps-only               # only refresh bunDepsHash
#   ./update.fish --target=catnip-desktop   # build a different app for hash discovery

set -l scriptDir (dirname (status filename))
set -l versionFile "$scriptDir/version.json"

for cmd in curl jq nix-prefetch-url nix awk
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

# ── Parse flags ──────────────────────────────────────────────────────────────

set -l electrobunVersionOverride ""
set -l depsOnly 0
set -l buildTarget "t3code-desktop"
for arg in $argv
    switch $arg
        case '--electrobun=*'
            set electrobunVersionOverride (string replace '--electrobun=' '' -- $arg)
        case --deps-only
            set depsOnly 1
        case '--target=*'
            set buildTarget (string replace '--target=' '' -- $arg)
        case '*'
            echo "Error: Unknown argument: $arg"
            echo "Usage: update.fish [--electrobun=VERSION] [--deps-only] [--target=PACKAGE]"
            exit 1
    end
end

# ── Helpers ──────────────────────────────────────────────────────────────────

function prefetchSriHash --argument-names url
    set -l raw (nix-prefetch-url --type sha256 $url 2>/dev/null | tail -1)
    if test -z "$raw"
        return 1
    end
    nix hash convert --to sri --hash-algo sha256 $raw
end

set -l flakeRoot (git -C $scriptDir rev-parse --show-toplevel 2>/dev/null)
if test -z "$flakeRoot"
    echo "Error: Not in a git checkout; cannot locate flake root"
    exit 1
end

# ── 1. Electrobun version + hashes ───────────────────────────────────────────

set -l currentElectrobun (jq -r .electrobun.version <$versionFile)
set -l targetElectrobun ""

if test "$depsOnly" = 1
    set targetElectrobun $currentElectrobun
    echo "[deps-only] Skipping electrobun refresh (keeping $currentElectrobun)"
else if test -n "$electrobunVersionOverride"
    set targetElectrobun $electrobunVersionOverride
    echo "[electrobun] Using override: $targetElectrobun"
else
    echo "[electrobun] Checking latest release on GitHub..."
    set targetElectrobun (curl -s https://api.github.com/repos/blackboardsh/electrobun/releases/latest | jq -r '.tag_name // empty' | string replace -r '^v' '')
    if test -z "$targetElectrobun"
        echo "Error: Could not fetch latest electrobun release"
        exit 1
    end
    echo "[electrobun] Latest: $targetElectrobun"
end

set -l newElectrobunCliHash (jq -r .electrobun.cliHash <$versionFile)
set -l newElectrobunCoreHash (jq -r .electrobun.coreHash <$versionFile)

if test "$targetElectrobun" != "$currentElectrobun"
    echo "[electrobun] $currentElectrobun -> $targetElectrobun"
    echo "[electrobun] Prefetching cli + core tarballs in parallel..."

    set -l cliTmp (mktemp)
    set -l coreTmp (mktemp)
    prefetchSriHash "https://github.com/blackboardsh/electrobun/releases/download/v$targetElectrobun/electrobun-cli-linux-x64.tar.gz" >$cliTmp &
    prefetchSriHash "https://github.com/blackboardsh/electrobun/releases/download/v$targetElectrobun/electrobun-core-linux-x64.tar.gz" >$coreTmp &
    wait

    set newElectrobunCliHash (string trim <$cliTmp)
    set newElectrobunCoreHash (string trim <$coreTmp)
    rm -f $cliTmp $coreTmp

    if test -z "$newElectrobunCliHash"
        echo "Error: Failed to fetch electrobun cli tarball for $targetElectrobun"
        exit 1
    end
    if test -z "$newElectrobunCoreHash"
        echo "Error: Failed to fetch electrobun core tarball for $targetElectrobun"
        exit 1
    end
else
    echo "[electrobun] Already at $currentElectrobun"
end

# ── 2. bunDepsHash via sentinel + nix build ──────────────────────────────────

set -l fakeHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

echo "[bun-deps] Writing sentinel version.json..."
jq -n \
    --arg ebVersion "$targetElectrobun" \
    --arg ebCliHash "$newElectrobunCliHash" \
    --arg ebCoreHash "$newElectrobunCoreHash" \
    --arg bunDepsHash "$fakeHash" \
    '{
        electrobun: {version: $ebVersion, cliHash: $ebCliHash, coreHash: $ebCoreHash},
        bunDepsHash: $bunDepsHash
    }' >$versionFile

echo "[bun-deps] Running nix build ($buildTarget) to discover bunDepsHash..."
set -l buildOutput (nix build --no-link "$flakeRoot#$buildTarget" 2>&1)

# All apps share the same shell template, so the bunDepsHash from any
# target is valid for all of them. Match any *-bun-deps-* derivation.
set -l newBunDepsHash (string join \n -- $buildOutput | awk '
    /hash mismatch in fixed-output derivation/ {
        if ($0 ~ /-bun-deps-/) {
            tracking = 1
        } else {
            tracking = 0
        }
        next
    }
    /got:[ \t]+sha256-/ && tracking {
        match($0, /sha256-[A-Za-z0-9+\/=]+/)
        print substr($0, RSTART, RLENGTH)
        tracking = 0
    }
')

if test -z "$newBunDepsHash"
    echo "Error: Could not extract bunDepsHash from build output."
    echo ""
    echo "Build output:"
    echo $buildOutput
    echo ""
    echo "Reverting version.json"
    git -C $flakeRoot checkout -- $versionFile
    exit 1
end

echo "[bun-deps] New bunDepsHash: $newBunDepsHash"

# ── Write final version.json ─────────────────────────────────────────────────

jq -n \
    --arg ebVersion "$targetElectrobun" \
    --arg ebCliHash "$newElectrobunCliHash" \
    --arg ebCoreHash "$newElectrobunCoreHash" \
    --arg bunDepsHash "$newBunDepsHash" \
    '{
        electrobun: {version: $ebVersion, cliHash: $ebCliHash, coreHash: $ebCoreHash},
        bunDepsHash: $bunDepsHash
    }' >$versionFile

# ── Verify ───────────────────────────────────────────────────────────────────

echo ""
echo "Verifying build ($buildTarget)..."
if nix build --no-link "$flakeRoot#$buildTarget" >/dev/null 2>&1
    echo "Build OK"
else
    echo "Warning: verification build failed. version.json was updated but"
    echo "$buildTarget no longer builds. Inspect with:"
    echo "  nix build $flakeRoot#$buildTarget"
    exit 1
end

echo ""
echo "Commit with:"
echo "  git add lib/desktop/electrobun/version.json"
echo "  git commit -m \"electrobun: refresh deps\""
