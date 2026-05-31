{
  stdenv,
  lib,
  fetchurl,
  dpkg,
  buildFHSEnv,
  iptables,
  iproute2,
  procps,
  cacert,
  libxml2,
  libidn2,
  zlib,
  sqlite,
  wireguard-tools,
  inetutils,
  systemd,
  nftables,
}:

let
  version = "5.0.0";

  nordvpn-base = stdenv.mkDerivation {
    pname = "nordvpn-base";
    inherit version;

    src = fetchurl {
      url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_${version}_amd64.deb";
      hash = "sha256:01j4vsn46xi316i77n97p6rqc9bkgp5adzvv4z47ss8601cgkgqp";
    };

    nativeBuildInputs = [ dpkg ];
    dontBuild = true;
    dontFixup = true;

    unpackPhase = "dpkg-deb -x $src .";

    installPhase = ''
      mkdir -p $out/bin $out/sbin $out/lib
      cp -r usr/* $out/ || true
      # Ensure nordvpnd is also findable in bin/
      ln -sf $out/sbin/nordvpnd $out/bin/nordvpnd || true
      # Put NordVPN's custom .so files where the linker can find them
      ln -sf $out/lib64/nordvpn/*.so $out/lib/ || true
      ln -sf $out/lib64/nordvpn/*.so $out/lib64/ || true
      mkdir -p $out/state
      cp -r var/lib/nordvpn/* $out/state/ || true
    '';
  };

  commonPkgs = [
    nordvpn-base
    iptables
    nftables
    iproute2
    procps
    cacert
    libxml2
    libidn2
    zlib
    sqlite
    stdenv.cc.cc.lib
    wireguard-tools
    inetutils
    systemd
  ];

  # FHS env for the CLI
  nordvpn-cli = buildFHSEnv {
    name = "nordvpn";
    inherit version;
    targetPkgs = _: commonPkgs;
    runScript = "nordvpn";
  };

  # FHS env for the daemon (binary is at /usr/sbin/nordvpnd in the FHS root)
  nordvpn-daemon = buildFHSEnv {
    name = "nordvpnd";
    inherit version;
    targetPkgs = _: commonPkgs;
    runScript = "/usr/sbin/nordvpnd";
  };

in
stdenv.mkDerivation {
  pname = "nordvpn";
  inherit version;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin $out/var/lib/nordvpn

    ln -s ${nordvpn-cli}/bin/nordvpn $out/bin/nordvpn
    ln -s ${nordvpn-daemon}/bin/nordvpnd $out/bin/nordvpnd

    # Copy initial state data
    cp -r ${nordvpn-base}/state/* $out/var/lib/nordvpn/ || true
  '';

  meta = {
    description = "NordVPN CLI and daemon";
    homepage = "https://nordvpn.com";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nordvpn";
  };
}
