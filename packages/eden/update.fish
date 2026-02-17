#!/usr/bin/env fish

# Update script for eden emulator and its dependencies
# Updates sources.json with latest versions and hashes
#
# Sources updated:
#   eden     - Main emulator (Gitea: git.eden-emu.dev/eden-emu/eden)
#   sirit    - SPIR-V compiler (GitHub: eden-emulator/sirit)
#   mcl      - MCL library (GitHub: azahar-emu/mcl)
#   frozen   - Immutable containers (GitHub: serge-sans-paille/frozen)
#   xbyak    - x86 JIT backend (GitHub: herumi/xbyak)
#   nx_tzdb  - Timezone database (Gitea: git.crueter.xyz/misc/tzdb_to_nx)
#
# Not updated (stable/reference-only):
#   compat-list  - Yuzu compatibility list (flathub/org.yuzu_emu.yuzu)
#   quazip       - Qt6 ZIP library (crueter-archive/quazip-qt6)

set -l scriptDir (dirname (status filename))
set -l sourcesFile "$scriptDir/sources.json"

# Check dependencies
for cmd in curl jq nix-prefetch-git nix-prefetch-url nix-hash
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

set -l updated 0
set -l sources (cat $sourcesFile)

echo "=== Eden Source Updater ==="
echo ""

# ── eden (main source from Gitea, version from GitHub Releases) ──────────────

echo "[ eden ] Checking..."
set -l edenCurrent (echo $sources | jq -r '.eden.version')
set -l edenLatest (curl -s 'https://api.github.com/repos/eden-emulator/Releases/releases/latest' | jq -r '.tag_name // empty')

if test -z "$edenLatest"
    echo "[ eden ] Warning: Could not fetch latest release"
else if test "$edenLatest" = "$edenCurrent"
    echo "[ eden ] Up to date ($edenCurrent)"
else
    echo "[ eden ] $edenCurrent -> $edenLatest"
    echo "[ eden ] Prefetching with submodules (this may take a while)..."
    set -l result (nix-prefetch-git --quiet --fetch-submodules \
        "https://git.eden-emu.dev/eden-emu/eden.git" --rev "$edenLatest" 2>&1)

    if test $status -ne 0
        echo "[ eden ] Error: Prefetch failed"
        echo $result
    else
        set -l rev (echo $result | jq -r .rev)
        set -l hash (echo $result | jq -r .hash)
        set sources (echo $sources | jq \
            --arg v "$edenLatest" --arg r "$rev" --arg h "$hash" \
            '.eden = {version: $v, rev: $r, hash: $h}')
        echo "[ eden ] Updated to $edenLatest (rev: "(string sub -l 7 $rev)")"
        set updated (math $updated + 1)
    end
end

# ── sirit (GitHub tag) ───────────────────────────────────────────────────────

echo "[ sirit ] Checking..."
set -l siritCurrent (echo $sources | jq -r '.sirit.version')
set -l siritLatest (curl -s 'https://api.github.com/repos/eden-emulator/sirit/releases/latest' \
    | jq -r '.tag_name // empty')
# Fall back to tags API if no releases exist
if test -z "$siritLatest"
    set siritLatest (curl -s 'https://api.github.com/repos/eden-emulator/sirit/tags?per_page=1' \
        | jq -r '.[0].name // empty')
end

if test -z "$siritLatest"
    echo "[ sirit ] Warning: Could not fetch latest tag"
else if test "$siritLatest" = "$siritCurrent"
    echo "[ sirit ] Up to date ($siritCurrent)"
else
    echo "[ sirit ] $siritCurrent -> $siritLatest"
    set -l result (nix-prefetch-git --quiet \
        "https://github.com/eden-emulator/sirit.git" --rev "$siritLatest" 2>&1)

    if test $status -ne 0
        echo "[ sirit ] Error: Prefetch failed"
        echo $result
    else
        set -l rev (echo $result | jq -r .rev)
        set -l hash (echo $result | jq -r .hash)
        set sources (echo $sources | jq \
            --arg v "$siritLatest" --arg r "$rev" --arg h "$hash" \
            '.sirit = {version: $v, rev: $r, hash: $h}')
        echo "[ sirit ] Updated to $siritLatest"
        set updated (math $updated + 1)
    end
end

# ── mcl (GitHub latest commit) ───────────────────────────────────────────────

echo "[ mcl ] Checking..."
set -l mclCurrent (echo $sources | jq -r '.mcl.rev')
set -l mclLatest (curl -s 'https://api.github.com/repos/azahar-emu/mcl/commits?per_page=1' \
    | jq -r '.[0].sha // empty')

if test -z "$mclLatest"
    echo "[ mcl ] Warning: Could not fetch latest commit"
else if test "$mclLatest" = "$mclCurrent"
    echo "[ mcl ] Up to date ("(string sub -l 7 $mclCurrent)")"
else
    echo "[ mcl ] Updating..."
    set -l result (nix-prefetch-git --quiet \
        "https://github.com/azahar-emu/mcl.git" --rev "$mclLatest" 2>&1)

    if test $status -ne 0
        echo "[ mcl ] Error: Prefetch failed"
        echo $result
    else
        set -l hash (echo $result | jq -r .hash)
        set sources (echo $sources | jq \
            --arg r "$mclLatest" --arg h "$hash" \
            '.mcl = {rev: $r, hash: $h}')
        echo "[ mcl ] Updated to "(string sub -l 7 $mclLatest)
        set updated (math $updated + 1)
    end
end

# ── frozen (GitHub latest commit) ────────────────────────────────────────────

echo "[ frozen ] Checking..."
set -l frozenCurrent (echo $sources | jq -r '.frozen.rev')
set -l frozenLatest (curl -s 'https://api.github.com/repos/serge-sans-paille/frozen/commits?per_page=1' \
    | jq -r '.[0].sha // empty')

if test -z "$frozenLatest"
    echo "[ frozen ] Warning: Could not fetch latest commit"
else if test "$frozenLatest" = "$frozenCurrent"
    echo "[ frozen ] Up to date ("(string sub -l 7 $frozenCurrent)")"
else
    echo "[ frozen ] Updating..."
    set -l result (nix-prefetch-git --quiet \
        "https://github.com/serge-sans-paille/frozen.git" --rev "$frozenLatest" 2>&1)

    if test $status -ne 0
        echo "[ frozen ] Error: Prefetch failed"
        echo $result
    else
        set -l hash (echo $result | jq -r .hash)
        set sources (echo $sources | jq \
            --arg r "$frozenLatest" --arg h "$hash" \
            '.frozen = {rev: $r, hash: $h}')
        echo "[ frozen ] Updated to "(string sub -l 7 $frozenLatest)
        set updated (math $updated + 1)
    end
end

# ── xbyak (GitHub tag) ───────────────────────────────────────────────────────

echo "[ xbyak ] Checking..."
set -l xbyakCurrent (echo $sources | jq -r '.xbyak.version')
set -l xbyakTag (curl -s 'https://api.github.com/repos/herumi/xbyak/releases/latest' \
    | jq -r '.tag_name // empty')
# Fall back to tags API if no releases exist
if test -z "$xbyakTag"
    set xbyakTag (curl -s 'https://api.github.com/repos/herumi/xbyak/tags?per_page=1' \
        | jq -r '.[0].name // empty')
end
# Strip leading 'v' if present (e.g. v7.22 -> 7.22)
set -l xbyakVersion (string replace -r '^v' '' "$xbyakTag")

if test -z "$xbyakTag"
    echo "[ xbyak ] Warning: Could not fetch latest tag"
else if test "$xbyakVersion" = "$xbyakCurrent"
    echo "[ xbyak ] Up to date ($xbyakCurrent)"
else
    echo "[ xbyak ] $xbyakCurrent -> $xbyakVersion"
    set -l result (nix-prefetch-git --quiet \
        "https://github.com/herumi/xbyak.git" --rev "$xbyakTag" 2>&1)

    if test $status -ne 0
        echo "[ xbyak ] Error: Prefetch failed"
        echo $result
    else
        set -l rev (echo $result | jq -r .rev)
        set -l hash (echo $result | jq -r .hash)
        set sources (echo $sources | jq \
            --arg v "$xbyakVersion" --arg r "$rev" --arg h "$hash" \
            '.xbyak = {version: $v, rev: $r, hash: $h}')
        echo "[ xbyak ] Updated to $xbyakVersion"
        set updated (math $updated + 1)
    end
end

# ── nx_tzdb (Gitea release) ──────────────────────────────────────────────────

echo "[ nx_tzdb ] Checking..."
set -l tzdbCurrent (echo $sources | jq -r '.nx_tzdb.version')
set -l tzdbLatest (curl -s 'https://git.crueter.xyz/api/v1/repos/misc/tzdb_to_nx/releases?limit=1' \
    | jq -r '.[0].tag_name // empty')

if test -z "$tzdbLatest"
    echo "[ nx_tzdb ] Warning: Could not fetch latest release"
else if test "$tzdbLatest" = "$tzdbCurrent"
    echo "[ nx_tzdb ] Up to date ($tzdbCurrent)"
else
    echo "[ nx_tzdb ] $tzdbCurrent -> $tzdbLatest"
    set -l url "https://git.crueter.xyz/misc/tzdb_to_nx/releases/download/$tzdbLatest/$tzdbLatest.tar.gz"
    set -l sha256 (nix-prefetch-url --unpack --type sha256 "$url" 2>/dev/null)

    if test -z "$sha256"
        echo "[ nx_tzdb ] Error: Failed to fetch/hash release"
    else
        set -l sriHash (nix-hash --to-sri --type sha256 $sha256)
        set sources (echo $sources | jq \
            --arg v "$tzdbLatest" --arg h "$sriHash" \
            '.nx_tzdb = {version: $v, hash: $h}')
        echo "[ nx_tzdb ] Updated to $tzdbLatest"
        set updated (math $updated + 1)
    end
end

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if test $updated -gt 0
    echo $sources | jq . >$sourcesFile
    set -l edenVersion (echo $sources | jq -r '.eden.version')
    echo "Updated $updated source(s)"
    echo ""
    echo "Commit with:"
    echo "  git add packages/eden/"
    echo "  git commit -m \"eden: update to $edenVersion\""
else
    echo "All sources up to date"
end
