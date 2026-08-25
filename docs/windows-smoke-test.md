# Windows physical-hardware smoke test

Release status is not complete until this checklist passes on a physical
Windows 11 x64 machine. Record the PC model, CPU, GPU, Windows build, firmware
virtualization state, QEMU version output, and Omarchy version with the result.

## Clean preparation

- [ ] Extract the release ZIP into a standard user folder.
- [ ] Launch through `Start-WindowsIntoOmarchy.cmd` without editing execution policy
      globally.
- [ ] Confirm unsupported Windows or missing virtualization produces a useful
      blocked state rather than attempting QEMU.
- [ ] Enable Windows Hypervisor Platform through the elevated helper.
- [ ] Restart if Windows requests it.
- [ ] Download QEMU and confirm the SHA-512 passes.
- [ ] Complete the normal QEMU installer into its default location.
- [ ] Download Omarchy and confirm the SHA-256 passes.
- [ ] Confirm a deliberately modified copy is quarantined and cannot launch.

## First installation

- [ ] The boot rail reports all four checks ready.
- [ ] Persistent launch opens one QEMU desktop window.
- [ ] Task Manager shows hardware virtualization active.
- [ ] Omarchy's installer boots from the read-only ISO.
- [ ] The installer sees exactly one writable 64 GB disk.
- [ ] No Windows disk, partition, home directory, or shared folder is visible.
- [ ] Complete a normal unencrypted installation for this alpha test.
- [ ] The installation reboots or cleanly returns to the installed disk.
- [ ] Create the owner account and reach the Omarchy desktop.

## Desktop behavior

- [ ] `Super + Space` opens the Omarchy launcher while QEMU has input capture.
- [ ] The documented release chord returns input to Windows.
- [ ] Pointer coordinates remain correct at window edges.
- [ ] Keyboard layout and common punctuation are correct.
- [ ] Networking works through the user-mode adapter.
- [ ] Speaker output works.
- [ ] Microphone input is either verified or explicitly recorded as unavailable.
- [ ] Window close and guest shutdown do not leave QEMU processes running.

## Persistence and recovery

- [ ] Create a uniquely named file, shut down, relaunch, and find it intact.
- [ ] Open a disposable session, create another file, shut down, and confirm the
      second file is gone while the persistent file remains.
- [ ] Attempt a second concurrent launch and confirm it is refused.
- [ ] Archive and reset; confirm the old disk appears beneath `Backups`.
- [ ] Confirm reset creates a new blank disk on the next launch.
- [ ] Restore the archived disk manually and confirm it still boots.

## Stress and evidence

- [ ] Run for at least 60 minutes with terminal, browser, editor, and video.
- [ ] Suspend and resume Windows once while the guest is shut down.
- [ ] Repeat on at least one Intel and one AMD host before a broad release.
- [ ] Collect launcher log, QEMU log, screenshots, and checklist without secrets.
- [ ] Record graphics responsiveness honestly; do not label v0.1 as
      GPU-accelerated until an accelerated backend is measured and verified.
