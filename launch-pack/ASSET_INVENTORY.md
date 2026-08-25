# Asset inventory

| ID | Asset | Purpose | Source or provenance | Constraints | Output path | Status | Blocker or next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A01 | Source tree | Inspectable implementation | Authored and contract-tested locally | Text source only | Repository `v0.1.0` | Ready | None |
| A02 | Release ZIP | Runnable source package | Deterministic package script | Excludes third-party binaries | `dist/Windows-Into-Onarchy-v0.1.0.zip` | Ready | Upload to draft release |
| A03 | SHA-256 manifest | Artifact integrity | Generated from A02 | Must match uploaded bytes | `dist/SHA256SUMS` | Ready | Upload to draft release |
| A04 | Wordmark SVG | Repository identity | Authored project asset | Not runtime evidence | `assets/wordmark.svg` | Ready | None |
| A05 | Product screenshot | Runtime proof | Not available | Must come from a real Windows run | Not created | Omitted | Capture after physical acceptance |
