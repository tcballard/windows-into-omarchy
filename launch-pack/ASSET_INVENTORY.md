# Asset inventory

| ID | Asset | Provenance | Constraint | Status | Next action |
| --- | --- | --- | --- | --- | --- |
| A01 | Verified factory payload parts and compliance records | Artifact `9604642515`, digest recorded in workflow | Each release asset below 2 GiB | Ready | Rehash during promotion |
| A02 | Online bootstrap installer | Built and verified in run `33012105407` | Unsigned; below 512 MiB guard | Ready | Resume draft upload |
| A03 | `factory-release.json` | Retargeted and verified in run `33012105407` | Exact `v0.3.0-rc.2` URLs | Ready | Resume draft upload |
| A04 | `SHA256SUMS` and `release-report.json` | Artifact `9623046437`, digest `sha256:574e860ff17931a3044ec518ae43d419c6496daebfb136d390f15344f2f0fed6` | Exhaustive release inventory | Ready | Resume draft upload |
| A05 | Physical Windows acceptance evidence | Real Windows 11 machine | Exact release installer | Blocked | Complete smoke test |
