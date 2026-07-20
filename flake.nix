{
  description = "Transactional, offline-ready lifecycle management for nixos-shell VMs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs supportedSystems;

      fakeImage =
        pkgs: name: label:
        pkgs.runCommand "${name}-${label}-image" { } ''
          mkdir -p "$out/bin"
          cp ${./tests/fake-runner.sh} "$out/bin/run-${name}-vm"
          chmod +x "$out/bin/run-${name}-vm"
          substituteInPlace "$out/bin/run-${name}-vm" --replace-fail '@LABEL@' '${label}'
          patchShebangs "$out/bin/run-${name}-vm"
        '';

      evaluationFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.default
            {
              system.stateVersion = "26.05";
              services.nixosShellVmManager = {
                enable = true;
                instances.test-vm = {
                  image = fakeImage pkgs "test-vm" "baseline";
                  healthCheck.command = "test -e /run/test-vm/healthy";
                  runner.relativePath = "bin/run-compatible-vm";
                };
              };
            }
          ];
        };
    in
    {
      lib.mkVM = import ./lib/mk-vm.nix;

      nixosModules = {
        default = import ./modules;
        nixos-shell-vm-manager = self.nixosModules.default;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          evaluation = evaluationFor system;
          invalidContradiction = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                system.stateVersion = "26.05";
                services.nixosShellVmManager = {
                  enable = true;
                  instances.invalid = {
                    image = fakeImage pkgs "invalid" "baseline";
                    healthCheck.command = "true";
                    activation = {
                      restartOnGuestShutdown = false;
                      rolloutCandidateOnGuestShutdown = true;
                    };
                  };
                };
              }
            ];
          };
          invalidJitter = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                system.stateVersion = "26.05";
                services.nixosShellVmManager = {
                  enable = true;
                  instances.invalid = {
                    image = fakeImage pkgs "invalid" "baseline";
                    healthCheck.command = "true";
                    activation.guestShutdownJitter = {
                      minSeconds = 4;
                      maxSeconds = 1;
                    };
                  };
                };
              }
            ];
          };
          invalidRunnerPath = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                system.stateVersion = "26.05";
                services.nixosShellVmManager = {
                  enable = true;
                  instances.invalid = {
                    image = fakeImage pkgs "invalid" "baseline";
                    healthCheck.command = "true";
                    runner.relativePath = "bin/../run-invalid-vm";
                  };
                };
              }
            ];
          };
          contradictionResult = builtins.tryEval (
            builtins.deepSeq invalidContradiction.config.system.build.toplevel true
          );
          jitterResult = builtins.tryEval (builtins.deepSeq invalidJitter.config.system.build.toplevel true);
          runnerPathResult = builtins.tryEval (
            builtins.deepSeq invalidRunnerPath.config.system.build.toplevel true
          );
        in
        {
          module-evaluation =
            assert evaluation.config.systemd.services.test-vm-vm.serviceConfig.Restart == "no";
            assert !evaluation.config.services.nixosShellVmManager.instances.test-vm.activation.startOnBoot;
            assert
              evaluation.config.services.nixosShellVmManager.instances.test-vm.runner.relativePath
              == "bin/run-compatible-vm";
            assert evaluation.config.system.extraDependencies != [ ];
            assert !contradictionResult.success;
            assert !jitterResult.success;
            assert !runnerPathResult.success;
            pkgs.runCommand "nixos-shell-vm-manager-module-evaluation" { } ''
              touch "$out"
            '';

          shellcheck =
            pkgs.runCommand "nixos-shell-vm-manager-shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                shellcheck ${./scripts/nixos-shell-vm-manager.sh} ${./tests/fake-runner.sh} ${./tests/test-manager.sh}
                touch "$out"
              '';

          module-tests =
            pkgs.runCommand "nixos-shell-vm-manager-module-tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  gnugrep
                  jq
                  qemu
                  util-linux
                ];
              }
              ''
                bash ${./tests/test-manager.sh} ${./scripts/nixos-shell-vm-manager.sh} ${./tests/fake-runner.sh}
                touch "$out"
              '';
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          systemd-integration = import ./tests/nixos-test.nix {
            inherit pkgs self;
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              jq
              nixfmt-tree
              shellcheck
            ];
          };
        }
      );
    };
}
