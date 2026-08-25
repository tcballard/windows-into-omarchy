# Launch brief

- Product: Windows Into Omarchy
- Release: Windows Into Omarchy v0.1.0
- Version: 0.1.0
- Build: deterministic source ZIP
- Release state: early-alpha draft release
- Release date or window: 25 August 2026
- Authoritative source: `config/runtime.lock.json` and the `v0.1.0` tag

## Audience and outcome

- Primary audience: Windows 11 x64 users who want to try Omarchy without repartitioning.
- User outcome: prepare and launch the official Omarchy installer in a contained VM.
- Launch objective: publish an inspectable first build for physical-Windows testing.
- Primary call to action: download the ZIP and follow README `First run`.
- Canonical destination: https://github.com/tcballard/windows-into-omarchy

## Availability and boundaries

- Platforms and minimum versions: Windows 11 x64 build 22000+, 8 GB host RAM minimum, firmware virtualization.
- Rollout or eligibility: public early alpha.
- Pricing: free, MIT-licensed project code; third-party components retain their licences.
- Material limitations: physical Windows acceptance is pending; graphics are VirtIO 2D/software-rendered.
- Required disclosures: independent project; not affiliated with Omarchy, Basecamp, Omacom, Microsoft, QEMU, or Try Omarchy.

## Delivery contract

- Included channels: repository front door, GitHub source, draft GitHub release.
- Deliberately omitted channels: website, social, demo video, store, marketplace, press.
- Format or submission constraints: source ZIP excludes QEMU and the Omarchy ISO; SHA-256 published separately.
- Accessibility requirements: launcher has keyboard focus states and readable text contrast; no screenshot is used as runtime proof.
- Publication authority: Tom explicitly authorised repository publication and a draft `v0.1.0` release.

## Evidence summary

- Release artifact or verified build: `dist/Windows-Into-Omarchy-v0.1.0.zip`.
- Tests and measurements: 15 Python contracts plus ZIP integrity and deterministic checksum verification.
- Specification and acceptance criteria: `docs/architecture.md` and `docs/windows-smoke-test.md`.
- Build logs and decisions: deterministic `scripts/package.py` output and this launch pack.
- Existing assets and copy: `README.md`, `assets/wordmark.svg`, and release notes.
