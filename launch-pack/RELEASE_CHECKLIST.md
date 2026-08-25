# Release checklist

| Gate | Requirement | Evidence or observation | Result | Owner | Next action |
| --- | --- | --- | --- | --- | --- |
| Release identity | Version, build, date, and availability agree | Runtime lock, package, README, installer and notes say v0.1.0 alpha | Pass | Codex | None |
| Claims | Every used claim is verified or visibly qualified | `CLAIMS_LEDGER.md` | Pass | Codex | Keep C07 removed |
| Assets | Required outputs exist and open correctly | ZIP integrity check; SVG/XML parse | Pass | Codex | Upload A02/A03 |
| Technical | Channel and packaging constraints pass | 15 contracts; deterministic package | Pass | Codex | Windows runtime gate remains separate |
| Accessibility | Text alternatives, focus and readability | WPF keyboard-focus states; no unsupported screenshot | Pass | Codex | Physical UI review pending |
| Privacy | No secrets or private data | Source and package inspection | Pass | Codex | None |
| Links | Destinations and calls to action work | Repository and publisher URLs checked | Pass | Codex | Verify draft release after creation |
| Provenance | Source and third-party notices exist | `LICENSE`, `THIRD_PARTY_NOTICES.md` | Pass | Codex | None |
| Authority | Publisher and action are explicit | User authorised commit, tag and draft release | Pass | Tom | Public release remains a later decision |
