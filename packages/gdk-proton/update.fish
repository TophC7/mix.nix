#!/usr/bin/env fish

# Update script for gdk-proton.
# Bumps to the latest GDK-Proton-Custom release, then re-locates the WineGDK
# xgameruntime.dll patch site (see default.nix) and pins the DLL hashes.

set -l scriptDir (dirname (status filename))
set -l versionsFile "$scriptDir/versions.json"
set -l dllPath 'files/lib/wine/x86_64-windows/xgameruntime.dll'

# HTTPClientProvider GetResult: size check, `jb`, then the buggy `mov %rdi,%rdx`
# feeding memcpy. The mov sits 10 bytes into the match.
set -l context '\x4c\x8b\x47\x08\x4c\x39\x46\x08\x72.'
set -l buggy "(?s-u)$context\x48\x89\xfa\xe8"
set -l fixed "(?s-u)$context\x48\x8b\x17\xe8"

# Check dependencies
for cmd in curl jq nix-prefetch-url nix-hash tar rg sha256sum dd
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        exit 1
    end
end

echo "Fetching latest release..."
set -l releaseJson (curl -fsSL 'https://api.github.com/repos/LukasPAH/GDK-Proton-Custom/releases/latest' | jq -c .)

if test -z "$releaseJson" -o "$releaseJson" = null
    echo "Error: Could not fetch latest release"
    exit 1
end

set -l latestTag (printf '%s' "$releaseJson" | jq -r .tag_name)
set -l asset (printf '%s' "$releaseJson" | jq -r 'first(.assets[] | select(.name | endswith(".tar.gz")) | .name) // empty')
set -l currentTag (jq -r .tag < $versionsFile)

echo "Latest: $latestTag"
echo "Current: $currentTag"

if test "$latestTag" = "$currentTag"
    echo "Already up to date"
    exit 0
end

if test -z "$asset"
    echo "Error: $latestTag has no .tar.gz asset"
    exit 1
end

set -l downloadUrl "https://github.com/LukasPAH/GDK-Proton-Custom/releases/download/$latestTag/$asset"
echo "Fetching hash for: $asset"
set -l prefetch (nix-prefetch-url --print-path --type sha256 "$downloadUrl" 2>/dev/null)

if test (count $prefetch) -ne 2
    echo "Error: Failed to download or hash the release"
    echo "URL: $downloadUrl"
    exit 1
end

set -l sriHash (nix-hash --to-sri --type sha256 $prefetch[1])

# Pull the DLL out and locate the patch site
set -l work (mktemp -d)
tar -x -z -f $prefetch[2] -O --wildcards "*/$dllPath" >$work/xgameruntime.dll

if rg -q -a $fixed $work/xgameruntime.dll
    echo "WineGDK memcpy bug is fixed upstream in $latestTag: drop the xgameruntime patch from default.nix"
    rm -r $work
    exit 1
end

set -l matches (rg -a -b -o $buggy $work/xgameruntime.dll | string split -f1 :)
if test (count $matches) -ne 1
    echo "Error: expected 1 patch site in xgameruntime.dll, found "(count $matches)
    echo "Re-derive the patch by disassembling HTTPClientProvider (see default.nix)"
    rm -r $work
    exit 1
end

set -l offset (math $matches[1] + 10)
set -l originalHash (sha256sum $work/xgameruntime.dll | string split -f1 ' ')
printf '\x48\x8b\x17' | dd of=$work/xgameruntime.dll bs=1 seek=$offset conv=notrunc status=none
set -l patchedHash (sha256sum $work/xgameruntime.dll | string split -f1 ' ')
rm -r $work

jq -n \
    --arg tag "$latestTag" \
    --arg asset "$asset" \
    --arg hash "$sriHash" \
    --argjson offset $offset \
    --arg originalHash "$originalHash" \
    --arg patchedHash "$patchedHash" \
    '{tag: $tag, asset: $asset, hash: $hash, xgameruntime: {offset: $offset, originalHash: $originalHash, patchedHash: $patchedHash}}' >$versionsFile

echo "Updated: $currentTag -> $latestTag (patch at offset $offset)"
echo ""
echo "Commit with:"
echo "  git add packages/gdk-proton/versions.json"
echo "  git commit -m \"gdk-proton: update to $latestTag\""
