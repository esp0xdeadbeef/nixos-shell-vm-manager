{
  pkgs,
  self,
}:
let
  makeImageAt =
    name: runnerName: label:
    pkgs.runCommand "${name}-${label}-image" { } ''
      mkdir -p "$out/bin"
      cp ${./fake-runner.sh} "$out/bin/run-${runnerName}-vm"
      chmod +x "$out/bin/run-${runnerName}-vm"
      substituteInPlace "$out/bin/run-${runnerName}-vm" --replace-fail '@LABEL@' '${label}'
      patchShebangs "$out/bin/run-${runnerName}-vm"
    '';
  makeImage = name: label: makeImageAt name name label;
  baseline = makeImage "test-vm" "baseline";
  good = makeImage "test-vm" "good";
  bad = makeImage "test-vm" "bad";
  interrupted = makeImage "test-vm" "interrupted";
  guestCandidate = makeImage "test-vm" "guest-candidate";
  compatibleBaseline = makeImageAt "alias-vm" "compatible" "compatible-baseline";
in
pkgs.testers.runNixOSTest {
  name = "nixos-shell-vm-manager-systemd";

  nodes.machine = { ... }: {
    imports = [ self.nixosModules.default ];
    system.stateVersion = "26.05";
    environment.systemPackages = [ pkgs.jq ];
    # This test service has no IP network access. Its local functional check,
    # image selection, promotion, and rollback must still work.
    systemd.services.test-vm-vm.serviceConfig.IPAddressDeny = "any";
    system.extraDependencies = [
      good
      bad
      interrupted
      guestCandidate
    ];
    services.nixosShellVmManager = {
      enable = true;
      instances.test-vm = {
        image = baseline;
        activation = {
          restartOnGuestShutdown = true;
          rolloutCandidateOnGuestShutdown = true;
          guestShutdownJitter.minSeconds = 0;
          guestShutdownJitter.maxSeconds = 0;
        };
        healthCheck = {
          command = ''
            label=$(cat /run/fake-vm/active 2>/dev/null || true)
            if test "$label" = interrupted && test ! -e /run/fake-vm/allow-interrupted; then
              touch /run/fake-vm/health-entered
              sleep 30
            fi
            test -n "$label" && test "$label" != bad
          '';
          timeoutSeconds = 1;
          retries = 3;
          intervalSeconds = 0;
        };
        runner.stopGraceSeconds = 1;
      };
      instances.alias-vm = {
        image = compatibleBaseline;
        healthCheck = {
          command = "test $(cat /run/fake-vm/active) = compatible-baseline";
          timeoutSeconds = 1;
          retries = 3;
          intervalSeconds = 0;
        };
        runner = {
          relativePath = "bin/run-compatible-vm";
          stopGraceSeconds = 1;
        };
      };
    };
  };

  testScript = ''
    import json

    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Host activation admitted baseline but startOnBoot=false preserved stop.
    machine.fail("systemctl is-active --quiet test-vm-vm.service")
    state = json.loads(machine.succeed("vm-status test-vm"))
    assert state["candidate"]["image"] == "${baseline}"
    machine.fail("test -e /run/fake-vm/active")

    machine.succeed("systemctl start test-vm-vm.service")
    machine.wait_until_succeeds("test $(jq -r .current.image /var/lib/nixos-shell-vm-manager/test-vm/state.json) = ${baseline}")
    machine.succeed("test $(cat /run/fake-vm/active) = baseline")
    machine.succeed("test -S /run/nixos-shell/test-vm.tmux")
    machine.succeed("tmux -S /run/nixos-shell/test-vm.tmux has-session -t vm")
    machine.succeed("test $(tmux -S /run/nixos-shell/test-vm.tmux display-message -p -t vm:0.0 '#{pane_pid}') = $(cat /run/nixos-shell-vm-manager/test-vm/runner.pid)")
    machine.succeed("tmux -S /run/nixos-shell/test-vm.tmux send-keys -t vm offline-console-probe Enter")
    machine.wait_until_succeeds("test $(cat /run/fake-vm/console-input) = offline-console-probe")

    # Explicit stop is retained across later candidate admission.
    machine.succeed("mkdir -p /var/lib/nixos-shell-vm-manager/persistent/test-vm")
    machine.succeed("echo durable > /var/lib/nixos-shell-vm-manager/persistent/test-vm/marker")
    machine.succeed("systemctl stop test-vm-vm.service")
    machine.succeed("test -e /run/nixos-shell-vm-manager/test-vm/stopped")
    machine.fail("test -S /run/nixos-shell/test-vm.tmux")
    machine.succeed("test $(jq -r .phase /var/lib/nixos-shell-vm-manager/test-vm/state.json) = idle")
    machine.succeed("nixos-shell-vm-manager register /etc/nixos-shell-vm-manager/instances/test-vm.conf ${good} local-working-tree integration-good")
    machine.fail("systemctl is-active --quiet test-vm-vm.service")

    # Explicit rollout authorizes start and promotion.
    machine.succeed("vm-rollout test-vm")
    machine.wait_until_succeeds("test $(jq -r .current.image /var/lib/nixos-shell-vm-manager/test-vm/state.json) = ${good}")
    machine.succeed("tmux -S /run/nixos-shell/test-vm.tmux has-session -t vm")

    # A stop during candidate health wins without quarantining the candidate or
    # starting recovery. The service remains explicitly stopped and idle.
    machine.succeed("rm -f /run/fake-vm/health-entered /run/fake-vm/allow-interrupted")
    machine.succeed("nixos-shell-vm-manager register /etc/nixos-shell-vm-manager/instances/test-vm.conf ${interrupted} local-working-tree integration-interrupted")
    machine.succeed("vm-rollout test-vm")
    machine.wait_until_succeeds("test -e /run/fake-vm/health-entered")
    machine.succeed("systemctl stop test-vm-vm.service")
    state = json.loads(machine.succeed("vm-status test-vm"))
    assert state["current"]["image"] == "${good}"
    assert state["candidate"]["image"] == "${interrupted}"
    assert state["failed"] is None
    assert state["phase"] == "idle"
    assert state["authority"]["explicitlyStopped"] is True
    machine.fail("systemctl is-active --quiet test-vm-vm.service")
    machine.succeed("nixos-shell-vm-manager register /etc/nixos-shell-vm-manager/instances/test-vm.conf ${good} host-generation integration-current")
    machine.succeed("systemctl start test-vm-vm.service")
    machine.wait_until_succeeds("test $(cat /run/fake-vm/active) = good")

    # Functional-health failure rolls back to the same proven current image.
    machine.succeed("nixos-shell-vm-manager register /etc/nixos-shell-vm-manager/instances/test-vm.conf ${bad} local-working-tree integration-bad")
    machine.succeed("vm-rollout test-vm")
    machine.wait_until_succeeds("test $(jq -r .failed.image /var/lib/nixos-shell-vm-manager/test-vm/state.json) = ${bad} && test $(jq -r .phase /var/lib/nixos-shell-vm-manager/test-vm/state.json) = running && test $(cat /run/fake-vm/active 2>/dev/null || true) = good")
    machine.succeed("test $(jq -r .current.image /var/lib/nixos-shell-vm-manager/test-vm/state.json) = ${good}")
    machine.succeed("test $(cat /run/fake-vm/active) = good")
    machine.succeed("tmux -S /run/nixos-shell/test-vm.tmux has-session -t vm")

    # Natural runner exit is guest shutdown and rolls a pending candidate out.
    machine.succeed("nixos-shell-vm-manager register /etc/nixos-shell-vm-manager/instances/test-vm.conf ${guestCandidate} local-working-tree guest-event")
    pid = machine.succeed("cat /run/nixos-shell-vm-manager/test-vm/runner.pid").strip()
    machine.succeed(f"kill -TERM {pid}")
    machine.wait_until_succeeds("test $(jq -r .current.image /var/lib/nixos-shell-vm-manager/test-vm/state.json) = ${guestCandidate}")
    machine.succeed("test $(cat /run/fake-vm/active) = guest-candidate")
    machine.succeed("tmux -S /run/nixos-shell/test-vm.tmux has-session -t vm")

    machine.succeed("test $(cat /var/lib/nixos-shell-vm-manager/persistent/test-vm/marker) = durable")
    machine.succeed("systemctl stop test-vm-vm.service")
    machine.succeed("test $(jq -r .phase /var/lib/nixos-shell-vm-manager/test-vm/state.json) = idle")

    # A configuration name may intentionally use a compatible runner name.
    machine.fail("systemctl is-active --quiet alias-vm-vm.service")
    machine.succeed("systemctl start alias-vm-vm.service")
    machine.wait_until_succeeds("test $(jq -r .current.image /var/lib/nixos-shell-vm-manager/alias-vm/state.json) = ${compatibleBaseline}")
    machine.succeed("test $(cat /run/fake-vm/active) = compatible-baseline")
    machine.succeed("systemctl stop alias-vm-vm.service")
    machine.succeed("test $(jq -r .phase /var/lib/nixos-shell-vm-manager/alias-vm/state.json) = idle")
  '';
}
