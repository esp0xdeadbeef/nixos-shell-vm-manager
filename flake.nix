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

      carrierWatcherFor =
        pkgs:
        pkgs.writeShellApplication {
          name = "nixos-shell-vm-carrier-watcher";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
            pkgs.systemd
          ];
          text = builtins.readFile ./scripts/carrier-watcher.sh;
        };

      qgaSystemdHealthFor =
        pkgs:
        pkgs.writeShellApplication {
          name = "nixos-shell-vm-qga-systemd-health";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
            pkgs.socat
          ];
          text = builtins.readFile ./scripts/qga-systemd-health.sh;
        };

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
                carrierControls.test-carrier = {
                  interface = "eth0";
                  instances = [ "test-vm" ];
                  requiredInterfaces = [
                    "vmbr1"
                    "vmbr4"
                  ];
                };
                carrierControls.test-carrier-dry = {
                  interface = "eth1";
                  instances = [ "test-vm" ];
                  dryRun = true;
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

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          "carrier-watcher" = carrierWatcherFor pkgs;
          "qga-systemd-health" = qgaSystemdHealthFor pkgs;
        }
      );

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
          invalidCarrierTarget = lib.nixosSystem {
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
                  };
                  carrierControls.invalid = {
                    interface = "eth0";
                    instances = [ "unknown" ];
                  };
                };
              }
            ];
          };
          invalidCarrierStartPolicy = lib.nixosSystem {
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
                    activation.startOnBoot = true;
                  };
                  carrierControls.invalid = {
                    interface = "eth0";
                    instances = [ "invalid" ];
                  };
                };
              }
            ];
          };
          invalidConsolePath = lib.nixosSystem {
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
                    console.socketPath = "relative/invalid.tmux";
                  };
                };
              }
            ];
          };
          invalidPinRefresh = lib.nixosSystem {
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
                    activation.refreshPins = true;
                  };
                };
              }
            ];
          };
          duplicateConsolePath = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                system.stateVersion = "26.05";
                services.nixosShellVmManager = {
                  enable = true;
                  instances.first = {
                    image = fakeImage pkgs "first" "baseline";
                    healthCheck.command = "true";
                    console.socketPath = "/run/nixos-shell/shared.tmux";
                  };
                  instances.second = {
                    image = fakeImage pkgs "second" "baseline";
                    healthCheck.command = "true";
                    console.socketPath = "/run/nixos-shell/shared.tmux";
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
          carrierTargetResult = builtins.tryEval (
            builtins.deepSeq invalidCarrierTarget.config.system.build.toplevel true
          );
          carrierStartPolicyResult = builtins.tryEval (
            builtins.deepSeq invalidCarrierStartPolicy.config.system.build.toplevel true
          );
          consolePathResult = builtins.tryEval (
            builtins.deepSeq invalidConsolePath.config.system.build.toplevel true
          );
          duplicateConsolePathResult = builtins.tryEval (
            builtins.deepSeq duplicateConsolePath.config.system.build.toplevel true
          );
          pinRefreshResult = builtins.tryEval (
            builtins.deepSeq invalidPinRefresh.config.system.build.toplevel true
          );
        in
        {
          module-evaluation =
            assert evaluation.config.systemd.services.test-vm-vm.serviceConfig.Restart == "always";
            assert evaluation.config.systemd.services.test-vm-vm.serviceConfig.RestartSec == "1s";
            assert
              evaluation.config.systemd.services.test-vm-vm.serviceConfig.RestartPreventExitStatus == [
                75
                78
              ];
            assert evaluation.config.systemd.services.test-vm-vm.serviceConfig.SuccessExitStatus == [ 75 ];
            assert !evaluation.config.services.nixosShellVmManager.instances.test-vm.activation.startOnBoot;
            assert
              evaluation.config.services.nixosShellVmManager.instances.test-vm.activation.restartOnGuestShutdown;
            assert !evaluation.config.services.nixosShellVmManager.instances.test-vm.activation.refreshPins;
            assert
              evaluation.config.services.nixosShellVmManager.instances.test-vm.pinRefresh.lockScope == "host";
            assert
              evaluation.config.services.nixosShellVmManager.instances.test-vm.runner.relativePath
              == "bin/run-compatible-vm";
            assert evaluation.config.services.nixosShellVmManager.instances.test-vm.console.enable;
            assert
              evaluation.config.services.nixosShellVmManager.instances.test-vm.console.socketPath
              == "/run/nixos-shell/test-vm.tmux";
            assert
              builtins.length (
                builtins.fromJSON (
                  builtins.unsafeDiscardStringContext evaluation.config.systemd.services.nixos-shell-test-carrier.environment.VM_CONFIGS_JSON
                )
              ) == 1;
            assert lib.hasSuffix "nixos-shell-vm-manager-test-vm.conf" (
              builtins.head (
                builtins.fromJSON (
                  builtins.unsafeDiscardStringContext evaluation.config.systemd.services.nixos-shell-test-carrier.environment.VM_CONFIGS_JSON
                )
              )
            );
            assert lib.elem "sys-subsystem-net-devices-vmbr1.device"
              evaluation.config.systemd.services.nixos-shell-test-carrier.after;
            assert lib.elem "sys-subsystem-net-devices-vmbr4.device"
              evaluation.config.systemd.services.nixos-shell-test-carrier.after;
            assert evaluation.config.systemd.services.nixos-shell-test-carrier.environment.DRY_RUN == "false";
            assert
              evaluation.config.systemd.services.nixos-shell-test-carrier-dry.environment.DRY_RUN == "true";
            assert evaluation.config.system.extraDependencies != [ ];
            assert !contradictionResult.success;
            assert !jitterResult.success;
            assert !runnerPathResult.success;
            assert !carrierTargetResult.success;
            assert !carrierStartPolicyResult.success;
            assert !consolePathResult.success;
            assert !duplicateConsolePathResult.success;
            assert !pinRefreshResult.success;
            pkgs.runCommand "nixos-shell-vm-manager-module-evaluation" { } ''
              touch "$out"
            '';

          shellcheck =
            pkgs.runCommand "nixos-shell-vm-manager-shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                shellcheck \
                  ${./scripts/carrier-watcher.sh} \
                  ${./scripts/nixos-shell-vm-manager.sh} \
                  ${./scripts/qga-systemd-health.sh} \
                  ${./tests/fake-runner.sh} \
                  ${./tests/test-carrier-watcher.sh} \
                  ${./tests/test-manager.sh} \
                  ${./tests/test-qga-systemd-health.sh}
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

          carrier-watcher-tests =
            pkgs.runCommand "nixos-shell-vm-manager-carrier-watcher-tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  gnugrep
                ];
              }
              ''
                bash ${./tests/test-carrier-watcher.sh} ${lib.getExe self.packages.${system}."carrier-watcher"}
                touch "$out"
              '';

          qga-systemd-health-tests =
            pkgs.runCommand "nixos-shell-vm-manager-qga-systemd-health-tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  gnugrep
                  jq
                  socat
                ];
              }
              ''
                bash ${./tests/test-qga-systemd-health.sh} ${
                  lib.getExe self.packages.${system}."qga-systemd-health"
                }
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
