{ pkgs, vmLogs }:
let
  # Real qcow2 disk images containing real ext4 filesystems with real log
  # files. This is what an operator analyses after a VM dies, so the test
  # exercises the actual attach/mount/extract/unmount path -- not a mock.

  # Shared guest payload for both images.
  guestFiles = ''
    mkdir -p guest/var/log/journal/0000 guest/etc
    printf 'kernel-boot-line\n' >guest/var/log/dmesg
    printf 'journal-entry\n' >guest/var/log/journal/0000/system.journal
    printf 'analysed-guest\n' >guest/etc/hostname
  '';

  # A bare ext4 filesystem with no partition table, labelled `nixos`: exactly
  # what qemu-vm.nix creates for useBootLoader = false, the default for this
  # repository's VMs.
  baseImage = pkgs.runCommand "vm-logs-base.qcow2" { nativeBuildInputs = [ pkgs.qemu ]; } ''
    ${guestFiles}

    truncate -s 64M root.raw
    ${pkgs.e2fsprogs}/bin/mkfs.ext4 -q -F -L nixos root.raw

    {
      echo "mkdir /var"
      echo "mkdir /var/log"
      echo "mkdir /var/log/journal"
      echo "mkdir /var/log/journal/0000"
      echo "mkdir /etc"
      echo "write $(pwd)/guest/var/log/dmesg /var/log/dmesg"
      echo "write $(pwd)/guest/var/log/journal/0000/system.journal /var/log/journal/0000/system.journal"
      echo "write $(pwd)/guest/etc/hostname /etc/hostname"
    } >commands.debugfs

    ${pkgs.e2fsprogs}/bin/debugfs -w -f commands.debugfs root.raw >/dev/null 2>&1
    ${pkgs.e2fsprogs}/bin/debugfs -R "cat /var/log/dmesg" root.raw 2>/dev/null \
      | grep -qx kernel-boot-line

    qemu-img convert -f raw -O qcow2 root.raw "$out"
  '';

  # The live disk is an overlay over a read-only backing image, mirroring the
  # runtime chain the manager produces.
  overlayImage = pkgs.runCommand "vm-logs-overlay.qcow2" { nativeBuildInputs = [ pkgs.qemu ]; } ''
    qemu-img create -f qcow2 -b ${baseImage} -F qcow2 "$out" 64M >/dev/null
  '';

  # An image with a GPT partition table and the root filesystem inside a
  # partition, i.e. the layout produced when a bootloader is used. The analyser
  # must find the root by probing, not assume a bare filesystem.
  partitionedImage =
    pkgs.runCommand "vm-logs-partitioned.qcow2" { nativeBuildInputs = [ pkgs.qemu ]; }
      ''
        ${guestFiles}
        printf 'partitioned-boot\n' >guest/var/log/dmesg

        truncate -s 128M disk.raw
        ${pkgs.parted}/bin/parted -s disk.raw \
          mklabel gpt \
          mkpart ESP fat32 1MiB 21MiB \
          mkpart root ext4 21MiB 121MiB \
          set 1 esp on >/dev/null

        ROOT_OFFSET=$((21 * 1024 * 1024))
        ${pkgs.e2fsprogs}/bin/mkfs.ext4 -q -F -L nixos -E offset=$ROOT_OFFSET disk.raw 100M

        {
          echo "mkdir /var"
          echo "mkdir /var/log"
          echo "mkdir /etc"
          echo "write $(pwd)/guest/var/log/dmesg /var/log/dmesg"
          echo "write $(pwd)/guest/etc/hostname /etc/hostname"
        } >commands.debugfs

        # debugfs addresses a filesystem inside a partition with ?offset=N.
        ${pkgs.e2fsprogs}/bin/debugfs -w -f commands.debugfs \
          "disk.raw?offset=$ROOT_OFFSET" >/dev/null 2>&1
        ${pkgs.e2fsprogs}/bin/debugfs -R "cat /var/log/dmesg" \
          "disk.raw?offset=$ROOT_OFFSET" 2>/dev/null | grep -qx partitioned-boot

        qemu-img convert -f raw -O qcow2 disk.raw "$out"
      '';
  # An image with a recognisable but non-Linux filesystem. The analyser must
  # refuse it as a guest root rather than mounting it blindly.
  unsupportedImage =
    pkgs.runCommand "vm-logs-unsupported.qcow2" { nativeBuildInputs = [ pkgs.qemu ]; }
      ''
        truncate -s 64M disk.raw
        ${pkgs.dosfstools}/bin/mkfs.vfat -F 32 -n ESP disk.raw >/dev/null
        qemu-img convert -f raw -O qcow2 disk.raw "$out"
      '';

  # An image with no filesystem at all.
  blankImage = pkgs.runCommand "vm-logs-blank.qcow2" { nativeBuildInputs = [ pkgs.qemu ]; } ''
    qemu-img create -f qcow2 "$out" 64M >/dev/null
  '';
in
pkgs.testers.runNixOSTest {
  name = "nixos-shell-vm-manager-vm-logs";

  nodes.machine =
    { ... }:
    {
      system.stateVersion = "26.05";
      environment.systemPackages = [
        vmLogs
        pkgs.qemu
        pkgs.e2fsprogs
        pkgs.jq
        pkgs.parted
      ];
      # NBD is the read-only attachment mechanism the analyser uses.
      boot.kernelModules = [ "nbd" ];
      boot.extraModprobeConfig = "options nbd nbds_max=16";
      virtualisation = {
        memorySize = 2048;
        diskSize = 4096;
      };
    };

  testScript = ''
    import json

    machine.start()
    machine.wait_for_unit("multi-user.target")

    machine.succeed("cp ${overlayImage} /root/vm.qcow2")
    machine.succeed("qemu-img info --backing-chain /root/vm.qcow2 | grep -q 'backing file'")

    # --- mount ---------------------------------------------------------------
    mountpoint = machine.succeed("vm-logs mount /root/vm.qcow2").strip()
    machine.succeed(f"test -d {mountpoint}")
    machine.succeed(f"mountpoint -q {mountpoint}")

    # The evidence is visible exactly as the guest left it.
    machine.succeed(f"grep -qx kernel-boot-line {mountpoint}/var/log/dmesg")

    # --- read-only enforcement ----------------------------------------------
    # The whole point of this tool is that analysis cannot alter evidence.
    machine.fail(f"touch {mountpoint}/var/log/injected")
    machine.fail(f"sh -c 'echo tampered >> {mountpoint}/var/log/dmesg'")

    # --- deterministic copy -------------------------------------------------
    machine.succeed("vm-logs collect /root/vm.qcow2 --dest /root/evidence")
    machine.succeed("test -f /root/evidence/var/log/dmesg")
    machine.succeed("grep -qx kernel-boot-line /root/evidence/var/log/dmesg")
    machine.succeed("grep -qx journal-entry /root/evidence/var/log/journal/0000/system.journal")

    # The manifest records what was and was not present.
    data = json.loads(machine.succeed("cat /root/evidence/manifest.json"))
    assert "/var/log/dmesg" in data["collected"], data
    assert "/var/log/journal" in data["collected"], data
    assert "/var/log/syslog" in data["missing"], data
    # An absent artifact must not leak an empty string into the arrays.
    assert "" not in data["missing"], data

    # collect reuses an existing mount instead of attaching twice, so the
    # interactive session started above is still live. (`jq -r`, not `-e`:
    # -e reflects the VALUE, and `false` is a non-zero exit.)
    machine.succeed("test \"$(vm-logs status /root/vm.qcow2 | jq -r .active)\" = true")
    machine.succeed("test \"$(vm-logs status /root/vm.qcow2 | jq -r .mounted)\" = true")

    # --- idempotent mount ---------------------------------------------------
    first = machine.succeed("vm-logs mount /root/vm.qcow2").strip()
    second = machine.succeed("vm-logs mount /root/vm.qcow2").strip()
    assert first == second, (first, second)
    machine.succeed("test \"$(grep -c . /sys/block/nbd0/pid)\" = 1")

    # --- umount -------------------------------------------------------------
    machine.succeed("vm-logs umount /root/vm.qcow2")
    machine.succeed(f"! mountpoint -q {mountpoint}")
    machine.succeed("test \"$(vm-logs status /root/vm.qcow2 | jq -r .active)\" = false")
    machine.succeed("! grep -rqs . /sys/block/nbd*/pid")

    # umount is idempotent.
    machine.succeed("vm-logs umount /root/vm.qcow2")

    # --- collect from a clean state releases everything --------------------
    machine.succeed("vm-logs collect /root/vm.qcow2 --dest /root/evidence-clean")
    machine.succeed("test -f /root/evidence-clean/var/log/dmesg")
    machine.succeed("test \"$(vm-logs status /root/vm.qcow2 | jq -r .active)\" = false")
    machine.succeed("test \"$(vm-logs status /root/vm.qcow2 | jq -r .mounted)\" = false")
    machine.succeed("! grep -rqs . /sys/block/nbd*/pid")

    # --- debugfs path (no mount at all) ------------------------------------
    # Operators on a host without mount privileges still get the evidence.
    machine.succeed("vm-logs collect /root/vm.qcow2 --dest /root/evidence2 --no-mount")
    machine.succeed("grep -qx kernel-boot-line /root/evidence2/var/log/dmesg")

    # --- explicit artifact selection ---------------------------------------
    machine.succeed("vm-logs collect /root/vm.qcow2 --dest /root/evidence3 --no-mount --path /etc/hostname")
    machine.succeed("grep -qx analysed-guest /root/evidence3/etc/hostname")
    machine.succeed("test ! -e /root/evidence3/var/log/dmesg")

    # --- stale session recovery --------------------------------------------
    # A session recorded on disk whose mount is gone (host crash, or a reboot
    # that cleared /tmp) must not block a fresh analysis of the same image.
    # The session key is sha256 of the canonical image PATH, not of its bytes.
    stale_key = machine.succeed(
        "printf %s /root/vm.qcow2 | sha256sum | cut -d' ' -f1"
    ).strip()
    machine.succeed(f"mkdir -p /run/vm-logs/{stale_key}")
    machine.succeed(
        f"cat > /run/vm-logs/{stale_key}/session.json <<'JSON'\n"
        '{"schemaVersion":1,"image":"/root/vm.qcow2","device":"/dev/nbd0",'
        '"mountpoint":"/tmp/vm-logs/gone.mount","offset":"","filesystem":"ext4",'
        '"label":"nixos","createdAt":"2020-01-01T00:00:00Z"}\n'
        "JSON"
    )
    machine.succeed("test \"$(vm-logs status /root/vm.qcow2 | jq -r .active)\" = true")
    fresh = machine.succeed("vm-logs mount /root/vm.qcow2").strip()
    assert fresh != "/tmp/vm-logs/gone.mount", fresh
    machine.succeed("vm-logs umount /root/vm.qcow2")

    # --- the analysed image is never modified ------------------------------
    # Read-only is the whole guarantee: the overlay bytes must be identical
    # after a full mount/collect/unmount cycle.
    before = machine.succeed("sha256sum /root/vm.qcow2").split()[0]
    machine.succeed("vm-logs mount /root/vm.qcow2")
    machine.succeed("vm-logs collect /root/vm.qcow2 --dest /root/evidence-hash")
    machine.succeed("vm-logs umount /root/vm.qcow2")
    after = machine.succeed("sha256sum /root/vm.qcow2").split()[0]
    assert before == after, (before, after)

    # --- a failed mount must not leak an attachment ------------------------
    # If the guest root cannot be mounted, the image is detached again instead
    # of leaving an NBD device the operator cannot see.
    machine.succeed("mkdir -p /root/notadir")
    machine.succeed("echo x > /root/notadir/file")
    machine.fail("vm-logs mount /root/vm.qcow2 --mountpoint /root/notadir/file")
    machine.succeed("! grep -rqs . /sys/block/nbd*/pid")
    machine.succeed("test \"$(vm-logs status /root/vm.qcow2 | jq -r .active)\" = false")

    # --- collect honours an explicit mountpoint ---------------------------
    machine.succeed("vm-logs collect /root/vm.qcow2 --dest /root/evidence-mp --mountpoint /tmp/vm-logs/custom.mount")
    machine.succeed("test -f /root/evidence-mp/var/log/dmesg")

    # --- input validation --------------------------------------------------
    # A block device or a directory is refused, not analysed.
    machine.fail("vm-logs mount /dev/null")
    machine.fail("vm-logs mount /root")
    machine.fail("vm-logs mount /root/does-not-exist.qcow2")

    # A file that is not a disk image is reported, not silently mounted.
    machine.succeed("echo notanimage > /root/garbage.qcow2")
    machine.fail("vm-logs mount /root/garbage.qcow2")
    machine.succeed("test \"$(vm-logs status /root/garbage.qcow2 | jq -r .active)\" = false")

    # --- an unsupported filesystem is refused, not mounted -----------------
    # A FAT/ESP-only image is a boot partition, not a guest root.
    machine.succeed("cp ${unsupportedImage} /root/fat.qcow2")
    machine.fail("vm-logs mount /root/fat.qcow2")
    machine.succeed("! grep -rqs . /sys/block/nbd*/pid")

    # An image with no filesystem is reported, not silently accepted.
    machine.succeed("cp ${blankImage} /root/blank.qcow2")
    machine.fail("vm-logs mount /root/blank.qcow2")
    machine.succeed("! grep -rqs . /sys/block/nbd*/pid")

    # --- partitioned image (bootloader layout) -----------------------------
    # Images built with a bootloader carry GPT with the root filesystem inside a
    # partition; the analyser must find it by probing, not assume a bare fs.
    machine.succeed("cp ${partitionedImage} /root/part.qcow2")
    part_mount = machine.succeed("vm-logs mount /root/part.qcow2").strip()
    machine.succeed(f"grep -qx partitioned-boot {part_mount}/var/log/dmesg")
    machine.succeed("vm-logs umount /root/part.qcow2")
  '';
}
