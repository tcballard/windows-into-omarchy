# Claims ledger

| ID | Claim | Evidence | Status | Qualification | Channels |
| --- | --- | --- | --- | --- | --- |
| C01 | The factory candidate passed the pinned guest, runtime and release assembly gates. | Runs `32958526312` and `32961734903`; recorded artifact digests | Verified | Automated evidence | Release |
| C02 | Promotion rehashes each part and each reconstructed archive before rebinding URLs. | `factory/retarget_release_manifest.py`; tests | Verified | Promotion workflow path | Release, repository |
| C03 | After publication, a tester downloads only the installer and first launch downloads supporting assets. | Bootstrap build mode; embedded `factory-release.json`; materializer | Qualified | Release must be public; first physical run pending | Release |
| C04 | Release asset URLs are bound to the exact repository, tag and filename. | Manifest builder, retargeter and runtime validator | Verified | GitHub release assets only | Release |
| C05 | The exact build reaches the Omarchy desktop on physical Windows. | `docs/windows-smoke-test.md` | Blocked | Acceptance has not run | Excluded |
| C06 | The installer is trusted by Windows without warnings. | No Authenticode signature | Removed | SmartScreen warning expected | Excluded |

