# Asset inventory

| ID | Asset | Provenance | Constraint | Status | Next action |
| --- | --- | --- | --- | --- | --- |
| A01 | Verified factory payload parts and compliance records | Artifact `9604642515`, digest recorded in workflow | Each release asset below 2 GiB | Ready | Rehash during promotion |
| A02 | Online bootstrap installer | Built and verified in run `33014004895` | Unsigned; below 512 MiB guard | Ready | Reuse only on an exact remote digest match |
| A03 | `factory-release.json` | Retargeted and verified in run `33014004895` | Exact `v0.3.0-rc.2` URLs | Ready | Reuse only on an exact remote digest match |
| A04 | `SHA256SUMS` and `release-report.json` | Artifact `9623937267`, digest `sha256:beddca0f9634a65f795c2306326ef7e6859f53226f73c9e675b26c63e711fb0f` | Exhaustive release inventory | Ready | Stream remaining assets, then verify the full draft |
| A06 | Partial RC2 draft inventory | 10 uploaded assets and verified artifact `9623937267` from run `33014004895` | Preserve only exact name, state, size and digest matches | Partial | Resume from the pinned artifact; stream missing assets and verify the exhaustive inventory |
| A05 | Physical Windows acceptance evidence | Real Windows 11 machine | Exact release installer | Blocked | Complete smoke test |
