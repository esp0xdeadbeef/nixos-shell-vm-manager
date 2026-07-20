{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nixosShellVmManager;
  inherit (lib)
    concatMapStringsSep
    escapeShellArg
    filterAttrs
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optional
    optionalString
    types
    ;

  bool = value: if value then "1" else "0";

  manager = pkgs.writeShellApplication {
    name = "nixos-shell-vm-manager";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      jq
      nix
      qemu
      socat
      systemd
      util-linux
    ];
    text = builtins.readFile ../scripts/nixos-shell-vm-manager.sh;
  };

  operatorPackage = pkgs.symlinkJoin {
    name = "nixos-shell-vm-manager-operator-commands";
    paths =
      map
        (
          command:
          pkgs.writeShellScriptBin command ''
            exec ${manager}/bin/nixos-shell-vm-manager dispatch-${lib.removePrefix "vm-" command} \
              ${escapeShellArg cfg.instanceConfigDirectory} "$@"
          ''
        )
        [
          "vm-update"
          "vm-rollout"
          "vm-status"
        ];
  };

  instanceModule = { name, ... }: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether this VM is managed.";
      };

      description = mkOption {
        type = types.str;
        default = "${name} (nixos-shell)";
      };

      image = mkOption {
        type = types.package;
        description = "Consumer-built baseline containing bin/run-${name}-vm.";
      };

      localFlakeAttribute = mkOption {
        type = types.str;
        default = "nixosConfigurations.${name}.config.system.build.nixos-shell";
        description = "Attribute built from an immutable local flake snapshot.";
      };

      activation = {
        startOnBoot = mkOption {
          type = types.bool;
          default = false;
        };
        restartOnGuestShutdown = mkOption {
          type = types.bool;
          default = true;
        };
        rolloutCandidateOnGuestShutdown = mkOption {
          type = types.bool;
          default = true;
        };
        useCandidateOnExplicitStart = mkOption {
          type = types.bool;
          default = true;
        };
        guestShutdownJitter = {
          minSeconds = mkOption {
            type = types.ints.unsigned;
            default = 1;
          };
          maxSeconds = mkOption {
            type = types.ints.unsigned;
            default = 4;
          };
        };
      };

      healthCheck = {
        command = mkOption {
          type = types.lines;
          description = "Mandatory VM-specific functional health command.";
        };
        timeoutSeconds = mkOption {
          type = types.ints.positive;
          default = 10;
        };
        retries = mkOption {
          type = types.ints.positive;
          default = 12;
        };
        intervalSeconds = mkOption {
          type = types.ints.unsigned;
          default = 5;
        };
        packages = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = "Packages placed on PATH for the functional health command.";
        };
      };

      storage = {
        ephemeralRoot = mkOption {
          type = types.bool;
          default = true;
        };
        rootDiskFile = mkOption {
          type = types.str;
          default = "${name}.qcow2";
        };
        persistentDisk = {
          enable = mkOption {
            type = types.bool;
            default = false;
          };
          fileName = mkOption {
            type = types.str;
            default = "state.qcow2";
          };
          size = mkOption {
            type = types.str;
            default = "100G";
          };
        };
      };

      runner = {
        arguments = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        qemuArguments = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Additional QEMU argv appended safely to the nixos-shell runner.";
        };
        stopGraceSeconds = mkOption {
          type = types.ints.positive;
          default = 30;
        };
      };
    };
  };

  instances = filterAttrs (_: instance: instance.enable) cfg.instances;

  configFileFor =
    name: instance:
    pkgs.writeText "nixos-shell-vm-manager-${name}.conf" ''
      VM_NAME=${escapeShellArg name}
      STATE_DIR=${escapeShellArg "${cfg.stateDirectory}/${name}"}
      RUNTIME_DIR=${escapeShellArg "${cfg.runtimeDirectory}/${name}"}
      PERSISTENT_DIR=${escapeShellArg "${cfg.persistentDirectory}/${name}"}
      GC_ROOT_DIR=${escapeShellArg "${cfg.gcRootDirectory}/${name}"}
      CONTROL_DIR=${escapeShellArg "${cfg.controlDirectory}/${name}"}
      LOCK_DIR=${escapeShellArg "${cfg.lockDirectory}/${name}"}
      BUILD_TOKEN_DIRECTORY=${escapeShellArg "${cfg.lockDirectory}/build-tokens"}
      MAX_CONCURRENT_BUILDS=${toString cfg.maxConcurrentBuilds}
      RUNNER_RELATIVE_PATH=${escapeShellArg "bin/run-${name}-vm"}
      RUNNER_ARGUMENTS_JSON=${escapeShellArg (builtins.toJSON instance.runner.arguments)}
      QEMU_ARGUMENTS_JSON=${escapeShellArg (builtins.toJSON instance.runner.qemuArguments)}
      HEALTH_COMMAND=${escapeShellArg instance.healthCheck.command}
      HEALTH_TIMEOUT_SECONDS=${toString instance.healthCheck.timeoutSeconds}
      HEALTH_RETRIES=${toString instance.healthCheck.retries}
      HEALTH_INTERVAL_SECONDS=${toString instance.healthCheck.intervalSeconds}
      START_ON_BOOT=${bool instance.activation.startOnBoot}
      RESTART_ON_GUEST_SHUTDOWN=${bool instance.activation.restartOnGuestShutdown}
      ROLLOUT_CANDIDATE_ON_GUEST_SHUTDOWN=${bool instance.activation.rolloutCandidateOnGuestShutdown}
      USE_CANDIDATE_ON_EXPLICIT_START=${bool instance.activation.useCandidateOnExplicitStart}
      JITTER_MIN_SECONDS=${toString instance.activation.guestShutdownJitter.minSeconds}
      JITTER_MAX_SECONDS=${toString instance.activation.guestShutdownJitter.maxSeconds}
      EPHEMERAL_ROOT=${bool instance.storage.ephemeralRoot}
      ROOT_DISK_FILE=${escapeShellArg instance.storage.rootDiskFile}
      PERSISTENT_DISK_ENABLE=${bool instance.storage.persistentDisk.enable}
      PERSISTENT_DISK_FILE=${escapeShellArg instance.storage.persistentDisk.fileName}
      PERSISTENT_DISK_SIZE=${escapeShellArg instance.storage.persistentDisk.size}
      STOP_GRACE_SECONDS=${toString instance.runner.stopGraceSeconds}
      LOCAL_FLAKE_ATTRIBUTE=${escapeShellArg instance.localFlakeAttribute}
      SYSTEMD_UNIT=${escapeShellArg "${name}-vm.service"}
      SYSTEMCTL_BIN=${escapeShellArg "${pkgs.systemd}/bin/systemctl"}
      NIX_BIN=${escapeShellArg "${pkgs.nix}/bin/nix"}
      REQUIRE_STORE_IMAGES=1
      ALLOW_UNPRIVILEGED=0
    '';

  instanceConfigs = lib.mapAttrs configFileFor instances;

  instanceAssertions = lib.flatten (
    mapAttrsToList (name: instance: [
      {
        assertion =
          !(
            instance.activation.rolloutCandidateOnGuestShutdown && !instance.activation.restartOnGuestShutdown
          );
        message = "${name}: candidate rollout on guest shutdown requires guest-shutdown restart";
      }
      {
        assertion =
          instance.activation.guestShutdownJitter.minSeconds
          <= instance.activation.guestShutdownJitter.maxSeconds;
        message = "${name}: guest-shutdown jitter minimum exceeds maximum";
      }
      {
        assertion = instance.healthCheck.command != "";
        message = "${name}: a functional healthCheck.command is mandatory";
      }
      {
        assertion = builtins.match "^[^/]+$" instance.storage.rootDiskFile != null;
        message = "${name}: storage.rootDiskFile must be a file name";
      }
      {
        assertion = builtins.match "^[^/]+$" instance.storage.persistentDisk.fileName != null;
        message = "${name}: storage.persistentDisk.fileName must be a file name";
      }
      {
        assertion = instance.localFlakeAttribute != "";
        message = "${name}: localFlakeAttribute must not be empty";
      }
    ]) instances
  );
in
{
  options.services.nixosShellVmManager = {
    enable = mkEnableOption "transactional nixos-shell VM management";

    instances = mkOption {
      type = types.attrsOf (types.submodule instanceModule);
      default = { };
    };

    maxConcurrentBuilds = mkOption {
      type = types.ints.positive;
      default = 1;
      description = "Maximum concurrent local candidate builds across VMs.";
    };

    stateDirectory = mkOption {
      type = types.str;
      default = "/var/lib/nixos-shell-vm-manager";
    };
    runtimeDirectory = mkOption {
      type = types.str;
      default = "/var/cache/nixos-shell-vm-manager";
    };
    persistentDirectory = mkOption {
      type = types.str;
      default = "/var/lib/nixos-shell-vm-manager/persistent";
    };
    gcRootDirectory = mkOption {
      type = types.str;
      default = "/nix/var/nix/gcroots/nixos-shell-vm-manager";
    };
    controlDirectory = mkOption {
      type = types.str;
      default = "/run/nixos-shell-vm-manager";
    };
    lockDirectory = mkOption {
      type = types.str;
      default = "/run/lock/nixos-shell-vm-manager";
    };
    instanceConfigDirectory = mkOption {
      type = types.str;
      default = "/etc/nixos-shell-vm-manager/instances";
      readOnly = true;
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = instances != { };
        message = "services.nixosShellVmManager requires at least one enabled instance";
      }
      {
        assertion = cfg.runtimeDirectory != cfg.persistentDirectory;
        message = "runtimeDirectory and persistentDirectory must be independent";
      }
    ]
    ++ instanceAssertions;

    environment.systemPackages = [
      manager
      operatorPackage
    ];

    environment.etc = mapAttrs' (
      name: source:
      nameValuePair "nixos-shell-vm-manager/instances/${name}.conf" {
        inherit source;
        mode = "0400";
      }
    ) instanceConfigs;

    system.extraDependencies = mapAttrsToList (_: instance: instance.image) instances;

    system.activationScripts.nixosShellVmManager = {
      deps = [ "etc" ];
      text = concatMapStringsSep "\n" (name: ''
        ${manager}/bin/nixos-shell-vm-manager register \
          ${instanceConfigs.${name}} \
          ${instances.${name}.image} \
          host-generation \
          ${escapeShellArg (toString instances.${name}.image)}
      '') (builtins.attrNames instances);
    };

    systemd.services = mapAttrs' (
      name: instance:
      nameValuePair "${name}-vm" {
        description = instance.description;
        wantedBy = optional instance.activation.startOnBoot "multi-user.target";
        after = [ "network.target" ];
        restartIfChanged = false;
        path = instance.healthCheck.packages;
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStartPre = "${manager}/bin/nixos-shell-vm-manager prepare-start ${instanceConfigs.${name}}";
          ExecStart = "${manager}/bin/nixos-shell-vm-manager supervise ${instanceConfigs.${name}}";
          ExecStop = "${manager}/bin/nixos-shell-vm-manager stop ${instanceConfigs.${name}} $MAINPID";
          Restart = "no";
          KillMode = "mixed";
          TimeoutStopSec = "${toString (instance.runner.stopGraceSeconds + 10)}s";
        };
      }
    ) instances;

    system.build.nixosShellVmManager = manager;
    system.build.nixosShellVmManagerOperatorCommands = operatorPackage;
  };
}
