from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class V03DocumentationContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.readme = (ROOT / "README.md").read_text(encoding="utf-8")
        cls.architecture = (ROOT / "docs/architecture.md").read_text(encoding="utf-8")
        cls.smoke = (ROOT / "docs/windows-smoke-test.md").read_text(encoding="utf-8")
        cls.releasing = (ROOT / "docs/releasing.md").read_text(encoding="utf-8")
        cls.compliance = (ROOT / "docs/distribution-compliance.md").read_text(encoding="utf-8")
        cls.notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
        cls.readme_words = " ".join(cls.readme.split())
        cls.smoke_words = " ".join(cls.smoke.split())

    def test_readme_names_factory_default_and_honest_status(self) -> None:
        self.assertIn("Development release candidate—not stable", self.readme)
        self.assertIn("Set up and enter Omarchy", self.readme)
        self.assertIn("without showing a Linux installer", self.readme)
        self.assertIn("developer and recovery fallback", self.readme_words)
        self.assertIn("fails closed to 2D", self.readme)
        self.assertNotIn("v0.3 stable release", self.readme.lower())

    def test_architecture_separates_factory_from_installer_fallback(self) -> None:
        self.assertIn("Default v0.3 path", self.architecture)
        self.assertIn("read-only Omarchy factory QCOW2", self.architecture)
        self.assertIn("private writable overlay", self.architecture)
        self.assertIn("ISO/`cidata`", self.architecture)
        self.assertIn("a release that falls back on a clean consumer machine has failed", self.architecture)

    def test_physical_acceptance_uses_exact_native_artifact(self) -> None:
        self.assertIn("exact signed", self.smoke)
        self.assertIn("WindowsIntoOmarchy.exe", self.smoke)
        self.assertIn("one Windows feature UAC prompt", self.smoke)
        self.assertIn("No QEMU installation UAC", self.smoke)
        self.assertIn("first-owner provisioning", self.smoke)
        self.assertIn("Windows 11 Home and Pro", self.smoke)
        self.assertIn("Intel PC and one AMD PC", self.smoke_words)

    def test_release_process_has_engineering_compliance_and_acceptance_gates(self) -> None:
        for phrase in (
            "Build and audit the guest",
            "Build and audit the portable runtime",
            "Compliance approval",
            "Build, sign and verify the installer",
            "Physical acceptance",
        ):
            self.assertIn(phrase, self.releasing)
        self.assertIn("`NOASSERTION`", self.releasing)
        self.assertIn("Code signing is not compliance approval", self.releasing)

    def test_compliance_explains_redistribution_without_claiming_legal_advice(self) -> None:
        self.assertIn("This is not legal advice", self.compliance)
        self.assertIn("what this project redistributes", self.compliance)
        self.assertIn("Giving a binary only to testers can still be distribution", self.compliance)
        self.assertIn("Authenticode answers", self.compliance)
        self.assertIn("114 linked DLLs", self.compliance)
        self.assertIn("No public binary release is approved", self.compliance)
        self.assertIn("Release stop/go gate", self.compliance)

    def test_high_level_notices_do_not_claim_to_be_complete(self) -> None:
        self.assertIn("not the complete notice set", self.notices)
        self.assertIn("Publication is blocked", self.notices)
        self.assertIn("generated, hash-bound runtime and guest", self.notices)


if __name__ == "__main__":
    unittest.main()
