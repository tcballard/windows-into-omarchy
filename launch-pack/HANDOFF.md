# Launch handoff

- Release: Windows Into Omarchy v0.3.0-rc.2
- Delivery: one downloaded bootstrap installer plus automatically fetched, checksum-bound assets from the same GitHub release
- Pack status: verified payload built; permanent draft asset upload recovery pending
- Publication authority: draft creation is authorised by the manual protected workflow; public publication remains an owner decision
- Exact next action: merge the RC2 recovery PR, run `prepare-v0.3.0-rc.2-bootstrap-release` on `main`, inspect the verified draft, then complete acceptance/review before choosing **Publish prerelease**

## Verified

- The existing factory candidate and its source workflow/artifact identities are pinned.
- Promotion run `33012105407` built and verified artifact `9623046437` for release commit `1600cec127d657f9a233acf7cbe66108e1562e87`.
- The annotated `v0.3.0-rc.2` tag points to that exact release commit and must not move.
- Manifest promotion rehashes every part and concatenated archive.
- The bootstrap installer requires the embedded RC manifest and omits the sidecar-copy directive.
- Final staging is digest-checked; the recovery workflow verifies every uploaded asset by release ID.

## Still blocked

- Completion and verification of the draft release asset inventory.
- A physical Windows 11 run of the exact promoted installer.
- Authenticode signing.
- Final binary redistribution approval.
- Anonymous asset URL checks, which become possible only after publication.
