# Wireless Nintendo Switch 2 controller bridge
{ lib, pkgs, ... }:
let
  inherit (pkgs) fetchFromGitHub makeWrapper stdenvNoCC;
  inherit (pkgs.python312Packages) buildPythonPackage;

  cython = buildPythonPackage {
    pname = "cython";
    version = "3.0.12";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "cython";
      repo = "cython";
      tag = "3.0.12";
      hash = "sha256-clJXjQb6rVECirKRUGX0vD5a6LILzPwNo7+6KKYs2pI=";
    };

    build-system = [
      pkgs.pkg-config
      pkgs.python312Packages.setuptools
    ];

    doCheck = false;
    strictDeps = true;
  };

  dbus-fast = buildPythonPackage {
    pname = "dbus-fast";
    version = "2.24.3";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "Bluetooth-Devices";
      repo = "dbus-fast";
      tag = "v2.24.3";
      hash = "sha256-RRVQCah44YTgRoGKtTDFU3dsaFbiUnKze3tZoCLM4uk=";
    };

    env.REQUIRE_CYTHON = 1;
    build-system = [
      cython
      pkgs.python312Packages.poetry-core
      pkgs.python312Packages.setuptools
    ];
    dependencies = [ pkgs.python312Packages.async-timeout ];

    pythonImportsCheck = [ "dbus_fast" ];
  };

  bleak = buildPythonPackage {
    pname = "bleak";
    version = "0.22.2";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "hbldh";
      repo = "bleak";
      tag = "v0.22.2";
      hash = "sha256-O8EvF+saJ0UBZ8MESM5gIRmk2wbA4HUDADiVUtXzXrY=";
    };

    build-system = [ pkgs.python312Packages.poetry-core ];
    dependencies = [
      pkgs.python312Packages.async-timeout
      dbus-fast
      pkgs.python312Packages.typing-extensions
    ];

    postPatch = ''
      substituteInPlace bleak/backends/bluezdbus/version.py \
        --replace-fail '"bluetoothctl"' '"${lib.getExe' pkgs.bluez "bluetoothctl"}"'
    '';

    pythonImportsCheck = [ "bleak" ];
  };

  python = pkgs.python312.withPackages (ps: [ bleak ps.evdev ]);
in
stdenvNoCC.mkDerivation {
  pname = "switch2-controllers";
  version = "0-unstable-2026-08-01";

  src = fetchFromGitHub {
    owner = "trevlars";
    repo = "switch2-controllers-linux";
    rev = "bdec56a65f00c3222313fe10d90d4622c84886c2";
    hash = "sha256-8FBf4EBFeibLxx7ltbtpECo59zP+NgqGqReuxC2Uowk=";
  };

  patches = [ ./detect-adapter.patch ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/switch2-controllers $out/bin
    cp -r ngc $out/lib/switch2-controllers/

    makeWrapper ${python}/bin/python $out/bin/switch2-controllers \
      --add-flags "-m ngc" \
      --set PYTHONPATH "$out/lib/switch2-controllers" \
      --suffix PATH : ${
        lib.makeBinPath (
          with pkgs;
          [
            bluez
            procps
            sudo
            systemd
          ]
        )
      }

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/switch2-controllers --help >/dev/null
  '';

  meta = {
    description = "Wireless Nintendo Switch 2 controller bridge";
    longDescription = ''
      Connects Nintendo Switch 2 controllers over Bluetooth LE and exposes
      standard uinput gamepads with rumble, motion, and battery reporting.
    '';
    homepage = "https://github.com/trevlars/switch2-controllers-linux";
    license = lib.licenses.mit;
    maintainers = [ "Toph" ];
    mainProgram = "switch2-controllers";
    platforms = lib.platforms.linux;
  };
}
