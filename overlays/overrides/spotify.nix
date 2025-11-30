# Update Spotify to latest version (upstream is outdated)
# Check for updates: curl -s -H 'X-Ubuntu-Series: 16' "https://api.snapcraft.io/api/v1/snaps/details/spotify?channel=stable" | jq '.revision,.download_sha512,.version'
{
  prev,
  ...
}:
{
  spotify = prev.spotify.overrideAttrs (_: rec {
    version = "1.2.74.477.g3be53afe";
    rev = "89";
    src = prev.fetchurl {
      url = "https://api.snapcraft.io/api/v1/snaps/download/pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7_${rev}.snap";
      hash = "sha512-mn1w/Ylt9weFgV67tB435CoF2/4V+F6gu1LUXY07J6m5nxi1PCewHNFm8/11qBRO/i7mpMwhcRXaiv0HkFAjYA==";
    };
  });
}
