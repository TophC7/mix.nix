#!/usr/bin/env fish

# Update script for t3code-desktop
#
# Refreshes every mutable hash in packages/t3code-desktop/version.json:
#
#   1. electrobun.{version,cliHash,coreHash}
#      - If --electrobun is passed, uses that version tag.
#      - Otherwise checks GitHub for the latest upstream release and uses it.
#      - cli and core tarballs are prefetched and hashed.
#
#   2. icon.{rev,hash}
#      - Follows packages/t3code/version.json's `rev` so the icon always
#        matches whatever commit t3code itself is pinned to.
#
#   3. bunDepsHash
#      - Sentineled to a fake hash, nix build is run, the "got:" line from
#        the resulting hash-mismatch error is captured and written back.
#        Same pattern as packages/t3code/update.fish.
#
# After writing the new version.json a verification build is run; if it
# fails, a warning is printed but version.json is NOT reverted (partial
# state is more debuggable than rolled-back state for this package).
#
# Usage:
#   ./update.fish                    # latest electrobun + icon sync
#   ./update.fish --electrobun=1.17.0   # pin a specific electrobun version
#   ./update.fish --deps-only        # only refresh bunDepsHash

set -l scriptDir (dirname (status filename))
set -l versionFile "$scriptDir/version.json"
set -l t3codeVersionFile "$scriptDir/../t3code/version.json"

for cmd in curl jq nix-prefetch-url nix awk
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

# ── Parse flags ──────────────────────────────────────────────────────────────

set -l electrobunVersionOverride ""
set -l depsOnly 0
for arg in $argv
    switch $arg
        case '--electrobun=*'
            set electrobunVersionOverride (string replace '--electrobun=' '' -- $arg)
        case '--deps-only'
            set depsOnly 1
        case '*'
            echo "Error: Unknown argument: $arg"
            echo "Usage: update.fish [--electrobun=VERSION] [--deps-only]"
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
    echo "[electrobun] Prefetching cli tarball..."
    set newElectrobunCliHash (prefetchSriHash "https://github.com/blackboardsh/electrobun/releases/download/v$targetElectrobun/electrobun-cli-linux-x64.tar.gz")
    if test -z "$newElectrobunCliHash"
        echo "Error: Failed to fetch electrobun cli tarball for $targetElectrobun"
        exit 1
    end
    echo "[electrobun] Prefetching core tarball..."
    set newElectrobunCoreHash (prefetchSriHash "https://github.com/blackboardsh/electrobun/releases/download/v$targetElectrobun/electrobun-core-linux-x64.tar.gz")
    if test -z "$newElectrobunCoreHash"
        echo "Error: Failed to fetch electrobun core tarball for $targetElectrobun"
        exit 1
    end
else
    echo "[electrobun] Already at $currentElectrobun"
end

# ── 2. Icon follows t3code's rev ─────────────────────────────────────────────

set -l currentIconRev (jq -r .icon.rev <$versionFile)
set -l newIconRev (jq -r .rev <$t3codeVersionFile)
set -l newIconHash (jq -r .icon.hash <$versionFile)

if test "$depsOnly" != 1 -a "$newIconRev" != "$currentIconRev"
    echo "[icon] $currentIconRev -> $newIconRev"
    echo "[icon] Prefetching icon at new t3code rev..."
    set newIconHash (prefetchSriHash "https://raw.githubusercontent.com/pingdotgg/t3code/$newIconRev/assets/prod/black-universal-1024.png")
    if test -z "$newIconHash"
        echo "Error: Failed to fetch icon at rev $newIconRev"
        exit 1
    end
else
    echo "[icon] Already at "(string sub -l 7 $currentIconRev)" (matches t3code)"
    set newIconRev $currentIconRev
end

# ── 3. bunDepsHash via sentinel + nix build ──────────────────────────────────

set -l fakeHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

echo "[bun-deps] Writing sentinel version.json..."
jq -n \
    --arg ebVersion "$targetElectrobun" \
    --arg ebCliHash "$newElectrobunCliHash" \
    --arg ebCoreHash "$newElectrobunCoreHash" \
    --arg bunDepsHash "$fakeHash" \
    --arg iconRev "$newIconRev" \
    --arg iconHash "$newIconHash" \
    '{
        electrobun: {version: $ebVersion, cliHash: $ebCliHash, coreHash: $ebCoreHash},
        bunDepsHash: $bunDepsHash,
        icon: {rev: $iconRev, hash: $iconHash}
    }' >$versionFile

echo "[bun-deps] Running nix build to discover bunDepsHash..."
set -l buildOutput (nix build --no-link "$flakeRoot#t3code-desktop" 2>&1)

# IMPORTANT: fish command substitution splits output on newlines into
# separate list elements; `echo $var` would re-join them with spaces,
# which collapses the multi-line build output into a single line and
# breaks awk's per-line matching. `string join \n` preserves the
# original line structure.
set -l newBunDepsHash (string join \n -- $buildOutput | awk '
    /hash mismatch in fixed-output derivation/ {
        if ($0 ~ /t3code-desktop-bun-deps-/) {
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
    --arg iconRev "$newIconRev" \
    --arg iconHash "$newIconHash" \
    '{
        electrobun: {version: $ebVersion, cliHash: $ebCliHash, coreHash: $ebCoreHash},
        bunDepsHash: $bunDepsHash,
        icon: {rev: $iconRev, hash: $iconHash}
    }' >$versionFile

# ── Verify ───────────────────────────────────────────────────────────────────

echo ""
echo "Verifying build..."
if nix build --no-link "$flakeRoot#t3code-desktop" >/dev/null 2>&1
    echo "Build OK"
else
    echo "Warning: verification build failed. version.json was updated but t3code-desktop"
    echo "no longer builds. Inspect with: nix build $flakeRoot#t3code-desktop"
    exit 1
end

echo ""
echo "Commit with:"
echo "  git add packages/t3code-desktop/version.json"
echo "  git commit -m \"t3code-desktop: refresh deps\""
