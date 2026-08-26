# Launch handoff

- Release: Windows Into Omarchy v0.3.0-rc.2
- Delivery: one downloaded bootstrap installer plus automatically fetched, checksum-bound assets from the same GitHub release
- Pack status: ready to merge and create the permanent draft
- Publication authority: draft creation is authorised by the manual protected workflow; public publication remains an owner decision
- Exact next action: merge the RC2 recovery PR, run `prepare-v0.3.0-rc.2-bootstrap-release` on `main`, inspect the verified draft, then complete acceptance/review before choosing **Publish prerelease**

## Verified

- The existing factory candidate and its source workflow/artifact identities are pinned.
- Manifest promotion rehashes every part and concatenated archive.
- The bootstrap installer requires the embedded RC manifest and omits the sidecar-copy directive.
- Final staging and uploaded GitHub asset inventory are digest-checked.

## Still blocked

- A physical Windows 11 run of the exact promoted installer.
- Authenticode signing.
- Final binary redistribution approval.
- Anonymous asset URL checks, which become possible only after publication.
