# Update Spotify to latest version (upstream is outdated)
# Check for updates: curl -s -H 'X-Ubuntu-Series: 16' "https://api.snapcraft.io/api/v1/snaps/details/spotify?channel=stable" | jq '.revision,.download_sha512,.version'
{
  prev,
  ...
}:
{
  spotify = prev.spotify.overrideAttrs (_: rec {
    version = "1.2.92.147.g5b8f9367";
    rev = "97";
    src = prev.fetchurl {
      url = "https://api.snapcraft.io/api/v1/snaps/download/pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7_${rev}.snap";
      hash = "sha512-Gk0/WjfgJZIG+2w4teaznAk/7evOXUsuCikDvOhmhAQ5ksQV99VeiYnE+OJf7hHnrPaHoueERvIkk7Psed/kwA==";
    };
  });
}
