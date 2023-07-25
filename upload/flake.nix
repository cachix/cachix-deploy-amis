{
  description = "Cachix Deploy AMIs";

  inputs = {
    nixpkgs-unstable.url = "github:/NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixos-generators-stable = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    nixos-generators-unstable = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
  };

  outputs = { self, nixpkgs-stable, nixpkgs-unstable, nixos-generators-stable, nixos-generators-unstable, poetry2nix, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: builtins.listToAttrs (map (name: { inherit name; value = f name; }) systems);

      mkAMI = pkg: system: pkg.nixosGenerate {
        format = "amazon";
        modules = [
          ./randomhost.nix
        {
          # set randomly later
          networking.hostName = "";

          services.cachix-agent.enable = true;
        }];
        inherit system;
      };
    in {
      packages = forAllSystems (
        system: {
          ami-stable = mkAMI nixos-generators-stable system;
          ami-unstable = mkAMI nixos-generators-unstable system;

          deploy-ami = poetry2nix.legacyPackages.${system}.mkPoetryApplication {
            projectDir = ./.;
          };
        }
      );

      devShell = forAllSystems (system:
        with (nixpkgs-stable.legacyPackages.${system}); mkShell { buildInputs = [awscli2 terraform jq moreutils]; }
      );
    };
}
