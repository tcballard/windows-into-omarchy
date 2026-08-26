# Windows physical-hardware acceptance

The release is not stable until this checklist passes against the exact signed
executable, installer, factory manifest and release assets. Record the artifact
hashes, PC model, CPU, GPU, Windows edition/build, account type, firmware
virtualisation state and test result. Redact usernames and secrets.

At minimum, run the complete path on Windows 11 Home and Pro, one Intel PC and
one AMD PC. At least one run should begin with WHPX disabled.

## Artifact identity

- [ ] Record SHA-256 values for the signed installer and native executable.
- [ ] Confirm Authenticode signatures and trusted timestamps validate offline
      after the certificate chain has been cached.
- [ ] Confirm the installed `factory-release.json` matches the release evidence.
- [ ] Confirm every runtime and guest part URL names the exact factory tag; no
      `latest`, redirects to mutable metadata, query token or alternate host is
      accepted.
- [ ] Confirm the installer contains the current licences, source-offer
      information, notices, SBOM references and unofficial/non-affiliation text.

## Native first-run surface

- [ ] Install for a standard Windows user and launch from the Start menu.
- [ ] Confirm the shortcut targets `WindowsIntoOnarchy.exe`, not PowerShell,
      `cmd.exe`, `wscript.exe` or the compatibility launcher.
- [ ] Confirm there is one Windows Into Onarchy progress surface and no visible
      terminal, QEMU setup wizard, ISO chooser or Linux installer.
- [ ] Confirm unsupported Windows/architecture/RAM produces one precise blocked
      state without attempting downloads or QEMU.
- [ ] With firmware virtualisation disabled, confirm the app asks for UEFI/BIOS
      action and does not loop the WHPX enable action.

## WHPX and restart resume

- [ ] With firmware virtualisation enabled and WHPX disabled, choose
      **Enable and continue**.
- [ ] Confirm one Windows feature UAC prompt appears. No QEMU installation UAC
      prompt may appear on the factory-default path.
- [ ] If possible, supply a different administrator account at UAC and confirm
      post-restart resume still belongs to the original interactive user.
- [ ] Cancel UAC once and confirm the one-time resume registration is removed.
- [ ] Repeat, approve, then confirm the app reports whether restart is required.
- [ ] Select **Restart and continue** and confirm the native app reopens exactly
      once after sign-in and continues without another click.
- [ ] Confirm the bounded resume entry is removed at the next verified boundary.

## Factory download and materialisation

- [ ] Observe determinate part-download progress on the same surface.
- [ ] Interrupt the network or app once; reopen and confirm verified completed
      parts are reused and the operation resumes safely.
- [ ] Modify a cached part and confirm it is quarantined before assembly.
- [ ] Confirm part, assembled-archive and extracted-payload size/digest checks
      all pass for the unmodified release.
- [ ] Confirm malformed ZIP paths, links, alternate data stream paths and
      excessive expansion are rejected by contract tests and never published.
- [ ] Confirm QEMU and `zstd.exe` came from the version-bound portable runtime;
      no system QEMU or PATH override is used by the public flow.
- [ ] Confirm Zstandard expands the guest with sparse-file support and the
      logical expanded size/SHA-256 matches the manifest.
- [ ] Confirm the factory QCOW2 is marked read-only before activation.
- [ ] Confirm `active.json` appears only after the complete receipt, runtime
      per-file audit, host capability probe and guest verification succeed.

## First owner and isolation

- [ ] Confirm the app creates `VM\<buildId>\omarchy.qcow2` as a QCOW2 overlay
      backed by the exact read-only factory.
- [ ] Confirm QEMU's inspected backing chain and the machine receipt match the
      active factory identity.
- [ ] Confirm the VM boots directly to Omarchy first-owner provisioning—not an
      Arch/Omarchy installer or shell.
- [ ] Confirm owner setup requests keyboard, username and password that are not
      present in the factory.
- [ ] Reach the Omarchy desktop and confirm no build account, reusable token,
      SSH/Tailscale identity or builder machine ID survives.
- [ ] From the guest, confirm no Windows disk, partition, home directory,
      clipboard, credential store, host folder or physical USB device is exposed.

## Runtime and display evidence

- [ ] Confirm Task Manager and QEMU logs show WHPX, not TCG, for the release run.
- [ ] Confirm `host-capabilities.json` belongs to the current factory runtime.
- [ ] On a host where VirGL/ANGLE or its smoke test is absent/fails, confirm QEMU
      launches with `virtio-vga` and `sdl,gl=off`.
- [ ] If `gpuAccelerationReady=true`, preserve the exact probe output and prove
      QEMU launches `virtio-vga-gl` with `sdl,gl=on` on that same host.
- [ ] Do not record “GPU accelerated” merely because WHPX is active.
- [ ] Exercise window resizing, pointer edges, keyboard layout, common
      punctuation and the input-release chord.
- [ ] Verify networking, speaker output and microphone status; record microphone
      as unavailable if it is not proved.
- [ ] Run terminal, browser, editor and video for at least 60 minutes.

## Persistence and recovery

- [ ] Create a uniquely named file, shut down cleanly, reopen with **Enter
      Omarchy**, and find it intact.
- [ ] Confirm second launch neither downloads assets nor shows owner setup.
- [ ] Open a disposable session, create another file, shut down, and confirm only
      the disposable change disappears.
- [ ] Attempt a concurrent launch and confirm the per-user mutex refuses it.
- [ ] Corrupt a copy of an overlay and confirm launch blocks with recovery
      guidance rather than modifying or booting it.
- [ ] Use **Archive & reset** and confirm the overlay and receipt move beneath
      `Backups` while the factory remains intact and read-only.
- [ ] Confirm a fresh overlay is created against the same active factory.
- [ ] Restore an archived overlay only through the documented engineering
      procedure and confirm its exact backing factory is required.

## Upgrade and fallback separation

- [ ] Install a test manifest with a new `buildId` and confirm the old overlay is
      not silently paired with the new factory.
- [ ] Confirm source/developer builds without `factory-release.json` explicitly
      label the ISO/`cidata` fallback.
- [ ] Confirm the signed consumer installer includes the factory manifest and
      therefore never enters fallback on a clean supported machine.
- [ ] Run the fallback separately as a recovery/development test; do not count it
      as factory-default release acceptance.

## Evidence closeout

- [ ] Collect redacted experience logs, QEMU logs, capability receipts,
      screenshots and this checklist.
- [ ] Record actual download bytes, peak temporary disk use, final factory disk
      allocation, overlay growth and first-owner time.
- [ ] Attach runtime/guest SBOMs, inventories, licence review, corresponding
      source and sanitisation evidence for these exact hashes.
- [ ] Record every limitation in release notes, including graphics fallback and
      hardware not tested.
- [ ] Have a release reviewer confirm that no unsigned or unreviewed artifact is
      described as stable.
