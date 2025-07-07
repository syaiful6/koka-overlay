{
  pkgs ? import <nixpkgs> {},
  system ? builtins.currentSystem,
}: let
  inherit (pkgs) lib stdenv fetchzip;
  sources = builtins.fromJSON (lib.strings.fileContents ./sources.json);

  mkKokaDerivation = version: system: releaseInfo:
    stdenv.mkDerivation {
      pname = "koka";
      inherit version;

      src = pkgs.fetchurl {
        url = releaseInfo.url;
        sha256 = releaseInfo.sha256;
      };
      sourceRoot = ".";

      installPhase = ''
        set -x # Enable shell tracing for debugging

        # With stripRoot=false, the contents are directly in the current directory.
        # We no longer need to find an 'extracted_dir'.
        echo "Contents of current directory after fetchzip (with stripRoot=false):"
        ls -R . # List all contents recursively for debugging

        # Create the necessary output directories in the Nix store.
        # We'll put the main executable in $out/bin, libraries in $out/lib/,
        # and shared data (including meta and potentially docs) in $out/share/.
        mkdir -p $out/bin
        mkdir -p $out/lib
        mkdir -p $out/share
        mkdir -p $out/share/koka/meta # For the 'meta' directory contents

        # Copy the Koka executable from its 'bin' subdirectory.
        # Paths now directly refer to the current directory.
        if [ -f "./bin/koka" ]; then
          cp "./bin/koka" $out/bin/koka
        else
          echo "Warning: koka executable not found in ./bin/"
        fi

        # Copy the 'lib/koka' directory and its contents, preserving the 'koka' subdirectory.
        # Paths now directly refer to the current directory.
        if [ -d "./lib/koka" ]; then
          cp -r "./lib/koka" $out/lib/
        else
          echo "Warning: lib/koka directory not found in ./"
        fi

        # Copy the 'meta' directory contents.
        # Paths now directly refer to the current directory.
        if [ -d "./meta" ]; then
          cp -r "./meta"/* $out/share/koka/meta/
        else
          echo "Warning: meta directory not found in ./"
        fi

        # Copy the 'share/koka' directory and its contents, preserving the 'koka' subdirectory.
        # Paths now directly refer to the current directory.
        if [ -d "./share/koka" ]; then
          cp -r "./share/koka" $out/share/
        else
          echo "Warning: share/koka directory not found in ./"
        fi

        echo "Contents of $out/bin:"
        ls -l $out/bin # Verify binary is in $out/bin
      '';

      meta = with lib; {
        description = "A functional language with effect types and handlers";
        homepage = "https://koka-lang.github.io/";
        #license = lib.licenses.apache20;
        platforms = [system];
      };
    };

  kokaVersionsForCurrentSystem =
    lib.mapAttrs (
      version: platforms: let
        releaseInfo = platforms.${system} or null;
      in
        if releaseInfo != null
        then mkKokaDerivation version system releaseInfo
        else null
    )
    sources;

  filteredKokaVersions = lib.filterAttrs (name: value: value != null) kokaVersionsForCurrentSystem;

  latestVersion = lib.lists.last (builtins.sort (x: y: (builtins.compareVersions x y) < 0) (lib.attrNames filteredKokaVersions));
in {
  versions = filteredKokaVersions;

  # Provide a 'default' Koka package for the current system (the latest available).
  default = lib.getAttr latestVersion filteredKokaVersions;
}
