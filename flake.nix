{
  description = "Nix overlay for the Koka programming language";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
      "x86_64-windows"
      "aarch64-windows"
    ];
    outputs = flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit system;};

        kokaPackages = import ./default.nix {inherit system pkgs;};
      in rec {
        # The packages exported by the Flake:
        # - default: latest /released/ version for the current system
        # - versions: attribute set of all tagged versions for the current system
        packages = {
          default = kokaPackages.default;
        } // (builtins.mapAttrs (name: pkg: pkg) kokaPackages.versions);

        # "Apps" so that `nix run` works.
        # `nix run .` will use the default app.
        apps = rec {
          default = apps.koka;
          koka = flake-utils.lib.mkApp {drv = packages.default;};
        };

        # nix fmt (optional, but good practice)
        formatter = pkgs.alejandra;

        # Default development shell for the current system.
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            packages.default
            curl
            jq
          ];
        };

        # For compatibility with older versions of the `nix` binary (optional)
        devShell = devShells.default;
      }
    );
  in
    outputs
    // {
      overlays.default = final: prev: {
        kokapkgs = {
          default = outputs.packages.${prev.system}.default;
          versions = builtins.removeAttrs outputs.packages.${prev.system} ["default"];
        };
      };
    };
}
