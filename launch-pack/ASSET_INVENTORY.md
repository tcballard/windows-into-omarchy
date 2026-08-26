# Asset inventory

| ID | Asset | Provenance | Constraint | Status | Next action |
| --- | --- | --- | --- | --- | --- |
| A01 | Verified factory payload parts and compliance records | Artifact `9604642515`, digest recorded in workflow | Each release asset below 2 GiB | Ready | Rehash during promotion |
| A02 | Online bootstrap installer | Built on Windows from the retargeted manifest | Unsigned; below 512 MiB guard | Ready to build | Run promotion workflow |
| A03 | `factory-release.json` | Retargeted from verified candidate after part/archive verification | Exact `v0.3.0-rc.2` URLs | Ready to build | Run promotion workflow |
| A04 | `SHA256SUMS` and `release-report.json` | Generated from final staged bytes | Exhaustive release inventory | Ready to build | Run promotion workflow |
| A05 | Physical Windows acceptance evidence | Real Windows 11 machine | Exact release installer | Blocked | Complete smoke test |
