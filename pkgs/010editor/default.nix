{
  lib,
  stdenv,
  autoPatchelfHook,
  makeDesktopItem,
  cups,
  libgcc,
  qt5,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "010editor";
  version = "14.0.1";
  src = builtins.fetchTarball {
    url = "https://download.sweetscape.com/010EditorLinux64Installer${finalAttrs.version}.tar.gz";
    sha256 = "sha256:09wwpd9rjm451hhl2crbllkx2iv06nwg9872cq9mcp1dyia7bscd";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    qt5.wrapQtAppsHook
  ];

  buildInputs = [
    cups
    libgcc
    qt5.qtbase
    stdenv.cc.cc
    makeWrapper
  ];

  installPhase = ''
    mkdir $out && cp -ar * $out

    # Patch executable and libs
    for file in \
      $out/010editor \
      $out/lib/*;
    do
      patchelf --set-rpath "${stdenv.cc.cc.lib}/lib:${stdenv.cc.cc.lib}/lib64" "$file"
    done

    # Don't use wrapped QT plugins since they are already included in the
    # package, else the program crashes because of the conflict.
    wrapProgram $out/010editor \
      --unset QT_PLUGIN_PATH

    mkdir $out/bin
    ln -s $out/010editor $out/bin/010editor

    # Copy the icon and generated desktop file
    install -D 010_icon_128x128.png -t $out/share/icons/hicolor/128x128/apps/
    install -D $desktopItem/share/applications/* -t $out/share/applications/
  '';

  desktopItem = makeDesktopItem {
    name = "010editor";
    exec = "010editor %f";
    icon = "010_icon_128x128";
    desktopName = "010 Editor";
    genericName = "Text and hex edtior";
    categories = [ "Development" ];
    mimeTypes = [
      "text/html"
      "text/plain"
      "text/x-c++hdr"
      "text/x-c++src"
      "text/xml"
    ];
  };

  meta = {
    description = "010editor";
    homepage = "https://www.sweetscape.com";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ ];
    platforms = lib.platforms.all;
    mainProgram = "010editor";
  };
})