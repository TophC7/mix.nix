# Based on https://github.com/Grantimatter/eden-flake/blob/main/package.nix
{ lib, pkgs, ... }:
let
  inherit (pkgs)
    stdenv
    cmake
    openssl
    boost
    fmt_11
    nlohmann_json
    lz4
    zlib
    zstd
    enet
    libopus
    vulkan-headers
    vulkan-utility-libraries
    spirv-tools
    spirv-headers
    simpleini
    discord-rpc
    cubeb
    vulkan-memory-allocator
    vulkan-loader
    libusb1
    pkg-config
    gamemode
    stb
    SDL2
    glslang
    python3
    httplib
    cpp-jwt
    fetchFromGitea
    ffmpeg-headless
    qt6
    fetchFromGitHub
    unordered_dense
    mbedtls
    xbyak
    zydis
    ;

  inherit (qt6)
    qtbase
    qtmultimedia
    qtwayland
    wrapQtAppsHook
    qttools
    qtwebengine
    qt5compat
    ;

  sources = lib.importJSON ./sources.json;

  quazip = stdenv.mkDerivation {
    pname = "quazip";
    version = "1.5-qt6";
    src = fetchFromGitHub {
      owner = "crueter-archive";
      repo = "quazip-qt6";
      rev = "f838774d6306eb5a500af9ab336ec85f01ebd7ec";
      hash = "sha256-Jp+v7uwoPxvarzOclgSnoGcwAPXKnm23yrZKtjJCHro=";
    };
    nativeBuildInputs = [
      cmake
    ];

    buildInputs = [
      qtbase
      qtmultimedia
      qtwayland
      wrapQtAppsHook
      qttools
      qtwebengine
      qt5compat
    ];
  };

  mcl = stdenv.mkDerivation {
    pname = "mcl";
    version = "unstable";
    src = fetchFromGitHub {
      owner = "azahar-emu";
      repo = "mcl";
      rev = sources.mcl.rev;
      hash = sources.mcl.hash;
    };

    nativeBuildInputs = [
      cmake
    ];

    buildInputs = [
      fmt_11
    ];
  };

  sirit = stdenv.mkDerivation {
    pname = "sirit";
    version = sources.sirit.version;
    src = fetchFromGitHub {
      owner = "eden-emulator";
      repo = "sirit";
      rev = sources.sirit.rev;
      hash = sources.sirit.hash;
    };

    nativeBuildInputs = [
      pkg-config
      cmake
    ];

    buildInputs = [
      spirv-headers
    ];

    cmakeFlags = [
      "-DSIRIT_USE_SYSTEM_SPIRV_HEADERS=ON"
    ];
  };

  nx_tzdb = builtins.fetchTarball {
    url = "https://git.crueter.xyz/misc/tzdb_to_nx/releases/download/${sources.nx_tzdb.version}/${sources.nx_tzdb.version}.tar.gz";
    sha256 = sources.nx_tzdb.hash;
  };

  xbyak_new = xbyak.overrideAttrs (_: {
    version = sources.xbyak.version;
    src = fetchFromGitHub {
      owner = "herumi";
      repo = "xbyak";
      rev = sources.xbyak.rev;
      hash = sources.xbyak.hash;
    };
  });

  frozen = stdenv.mkDerivation {
    pname = "frozen";
    version = "unstable";
    src = fetchFromGitHub {
      owner = "serge-sans-paille";
      repo = "frozen";
      rev = sources.frozen.rev;
      hash = sources.frozen.hash;
    };

    nativeBuildInputs = [
      cmake
    ];
  };

in
stdenv.mkDerivation (finalAttrs: {
  pname = "eden";
  version = sources.eden.version;
  src = fetchFromGitea {
    domain = "git.eden-emu.dev";
    owner = "eden-emu";
    repo = "eden";
    rev = sources.eden.rev;
    hash = sources.eden.hash;
    fetchSubmodules = true;
  };

  patches = [
    ./discord-rpc-compat.patch
  ];

  nativeBuildInputs = [
    cmake
    glslang
    pkg-config
    python3
    qttools
    wrapQtAppsHook
    mcl
    frozen
  ];

  buildInputs = [
    vulkan-headers
    qt5compat
    discord-rpc
    mcl
    boost
    nx_tzdb
    cpp-jwt
    cubeb
    enet
    ffmpeg-headless
    fmt_11
    gamemode
    httplib
    openssl
    libopus
    libusb1
    lz4
    mbedtls
    nlohmann_json
    qtbase
    qtmultimedia
    qtwayland
    qtwebengine
    SDL2
    quazip
    simpleini
    spirv-tools
    spirv-headers
    sirit
    stb
    unordered_dense
    vulkan-memory-allocator
    vulkan-utility-libraries
    xbyak_new
    zlib
    zstd
    zydis
  ];

  # dontFixCmake = true;

  __structuredAttrs = true;
  cmakeFlags = [
    # actually has a noticeable performance impact
    (lib.cmakeBool "YUZU_ENABLE_LTO" true)
    (lib.cmakeBool "YUZU_TESTS" false)
    (lib.cmakeBool "DYNARMIC_TESTS" false)

    (lib.cmakeBool "ENABLE_QT6" true)
    (lib.cmakeBool "ENABLE_QT_TRANSLATION" true)
    (lib.cmakeBool "ENABLE_OPENSSL" true)

    # use system libraries
    # NB: "external" here means "from the externals/ directory in the source",
    # so "false" means "use system"
    (lib.cmakeBool "YUZU_USE_EXTERNAL_SDL2" false)
    (lib.cmakeBool "YUZU_USE_EXTERNAL_VULKAN_HEADERS" false)
    (lib.cmakeBool "YUZU_USE_EXTERNAL_VULKAN_UTILITY_LIBRARIES" false)
    (lib.cmakeBool "YUZU_USE_EXTERNAL_VULKAN_SPIRV_TOOLS" false)
    (lib.cmakeBool "YUZU_USE_CPM" false)
    (lib.cmakeBool "CPMUTIL_FORCE_SYSTEM" true)

    # nx_tzdb
    (lib.cmakeFeature "YUZU_TZDB_PATH" "${nx_tzdb}")

    # don't check for missing submodules
    (lib.cmakeBool "YUZU_CHECK_SUBMODULES" false)

    # enable some optional features
    (lib.cmakeBool "YUZU_USE_QT_WEB_ENGINE" true)
    (lib.cmakeBool "YUZU_USE_QT_MULTIMEDIA" true)
    (lib.cmakeBool "USE_DISCORD_PRESENCE" true)

    # We dont want to bother upstream with potentially outdated compat reports
    (lib.cmakeBool "YUZU_ENABLE_COMPATIBILITY_REPORTING" false)
    (lib.cmakeBool "ENABLE_COMPATIBILITY_LIST_DOWNLOAD" true)

    (lib.cmakeFeature "TITLE_BAR_FORMAT_IDLE" "eden | ${finalAttrs.version} (nixpkgs) {}")
    (lib.cmakeFeature "TITLE_BAR_FORMAT_RUNNING" "eden | ${finalAttrs.version} (nixpkgs) | {}")

    # Dev
    (lib.cmakeBool "SIRIT_USE_SYSTEM_SPIRV_HEADERS" true)
    (lib.cmakeFeature "CMAKE_CXX_FLAGS" "-Wno-error -Wno-array-parameter -Wno-stringop-overflow")
  ];

  env = {
    NIX_CFLAGS_COMPILE = lib.optionalString stdenv.hostPlatform.isx86_64 "-msse4.2";
  };

  qtWrapperArgs = [
    "--prefix LD_LIBRARY_PATH : ${vulkan-loader}/lib"
  ];

  preConfigure = ''
    # Provide version info for builds without .git
    echo "${finalAttrs.version}" > GIT-REFSPEC
    echo "${sources.eden.rev}" > GIT-COMMIT
    echo "${finalAttrs.version}" > GIT-TAG
  '';

  postInstall = ''
    install -Dm644 $src/dist/72-yuzu-input.rules $out/lib/udev/rules.d/72-yuzu-input.rules
  '';

  meta = {
    description = "Nintendo Switch video game console emulator";
    homepage = "https://eden-emu.dev/";
    downloadPage = "https://eden-emu.dev/download";
    changelog = "https://github.com/eden-emulator/Releases/releases";
    mainProgram = "eden";
    desktopFileName = "dist/dev.eden_emu.eden.desktop";
  };
})
