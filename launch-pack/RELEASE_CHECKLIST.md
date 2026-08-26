# Release checklist

| Gate | Evidence | Result | Next action |
| --- | --- | --- | --- |
| Identity | Product `Windows Into Omarchy`, version `0.3.0`, tag `v0.3.0-rc.2` | Pass | Preserve exact values |
| Source artifact | Run, artifact ID, outer digest, inner checksums and source installer hash pinned | Pass | Workflow re-verifies |
| Bootstrap contract | RC tag support, exact repository URLs, no sidecar directive | Pass | Windows workflow build |
| Release integrity | Parts, concatenated archives, staged assets and uploaded inventory rehashed | Pass by contract | Confirm workflow run |
| Naming | Canonical `Windows Into Omarchy` product name used throughout | Pass | Preserve exact name |
| Signing | Installer is unsigned | Qualified | Expect SmartScreen; sign before stable release |
| Physical Windows | Exact release not yet accepted | Blocked | Run `docs/windows-smoke-test.md` |
| Distribution | Final binary review pending | Blocked | Owner/legal review before publication |
| Publication | Automation stops at protected draft | Pass | Owner makes publication decision |
