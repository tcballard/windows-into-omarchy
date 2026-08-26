# Launch handoff

- Release: Windows Into Omarchy v0.3.0-rc.2
- Delivery: one downloaded bootstrap installer plus automatically fetched, checksum-bound assets from the same GitHub release
- Pack status: verified payload built; permanent draft contains 10 verified small assets; streaming upload recovery pending
- Publication authority: draft creation is authorised by the manual protected workflow; public publication remains an owner decision
- Exact next action: merge the RC2 streaming-upload recovery PR, run `prepare-v0.3.0-rc.2-bootstrap-release` on `main`, inspect the verified draft, then complete acceptance/review before choosing **Publish prerelease**

## Verified

- The existing factory candidate and its source workflow/artifact identities are pinned.
- Promotion run `33014004895` built and verified artifact `9623937267` (digest `sha256:beddca0f9634a65f795c2306326ef7e6859f53226f73c9e675b26c63e711fb0f`) for release commit `1600cec127d657f9a233acf7cbe66108e1562e87`.
- The draft accepted 10 small assets with GitHub-recorded sizes and SHA-256 digests before buffered upload of the first large asset exhausted runner memory.
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
