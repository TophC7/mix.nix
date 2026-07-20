#!/usr/bin/env fish

# Update db.go from Wii U Downloader API and adapt it to the current library API.

set -l script_dir (dirname (status -f))
set -l db_file "$script_dir/db.go"
set -l tmp_file (mktemp)

for cmd in curl grep perl
    if not command -q $cmd
        echo "Error: Required command '$cmd' not found"
        rm -f "$tmp_file"
        exit 1
    end
end

echo "Updating Wii U Downloader database..."

if not curl --fail --silent --show-error --http1.1 \
        -H "User-Agent: NUSspliBuilder/2.1" \
        "https://napi.v10lator.de/db?t=go" \
        -o "$tmp_file"
    echo "Error: Failed to download db.go"
    rm -f "$tmp_file"
    exit 1
end

# Upstream defines TitleEntry in gtitles.go and expects the generated database
# to initialize TitleDatabase rather than declare its own type and variable.
perl -0pi -e 's/type TitleEntry struct \{.*?\}\s*//s; s/var titleEntry = /func init() {\n\tTitleDatabase = /' "$tmp_file"
printf '\n}\n' >>"$tmp_file"

if not grep -q '^package wiiudownloader' "$tmp_file" \
        || not grep -q '^func init()' "$tmp_file" \
        || not grep -q 'TitleDatabase = ' "$tmp_file"
    echo "Error: Downloaded database has an unexpected format"
    rm -f "$tmp_file"
    exit 1
end

mv "$tmp_file" "$db_file"

echo "Successfully updated db.go"
set -l timestamp (head -2 "$db_file" | tail -1)
echo "⌛ $timestamp"
