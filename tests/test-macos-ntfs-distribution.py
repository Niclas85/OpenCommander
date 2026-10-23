#!/usr/bin/env python3
"""Synthetic profile policy tests. No account, signing, mount or network calls."""
import copy
import datetime
import importlib.util
import pathlib
import unittest

root = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ntfs_distribution", root / "scripts/check-macos-ntfs-distribution.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ProfilePolicy(unittest.TestCase):
    team = "TESTTEAM01"
    identifier = "com.github.niklaus85.OpenCommander.NTFSModuleV2"

    def setUp(self):
        self.profile = {
            "TeamIdentifier": [self.team], "ProvisionsAllDevices": True,
            "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
            "Entitlements": {"com.apple.application-identifier": self.team + "." + self.identifier,
                             "com.apple.developer.fskit.fsmodule": True},
        }

    def check(self, value):
        gate.check_profile(value, self.identifier, self.team, True)

    def test_unrestricted_matching_profile(self):
        self.check(self.profile)

    def test_device_lists_never_published(self):
        for value in [[], ["SYNTHETIC-NOT-A-DEVICE"]]:
            with self.subTest(value=value), self.assertRaises(gate.Refused):
                self.check({**self.profile, "ProvisionedDevices": value})

    def test_unrestricted_boolean_required(self):
        for value in [False, None, 1, "true"]:
            with self.subTest(value=value), self.assertRaises(gate.Refused):
                self.check({**self.profile, "ProvisionsAllDevices": value})

    def test_mismatch_or_expiration(self):
        for changes in [{"TeamIdentifier": ["OTHERTEAM1"]},
                        {"ExpirationDate": datetime.datetime.now() - datetime.timedelta(days=1)},
                        {"ExpirationDate": "tomorrow"}]:
            with self.subTest(changes=changes), self.assertRaises(gate.Refused):
                self.check({**self.profile, **changes})

    def test_required_exact_entitlements(self):
        for changes in [{"get-task-allow": True},
                        {"com.apple.security.get-task-allow": True},
                        {"com.apple.application-identifier": self.team + ".*"},
                        {"com.apple.developer.fskit.fsmodule": False},
                        {"com.apple.developer.fskit.fsmodule": 1}]:
            value = copy.deepcopy(self.profile)
            value["Entitlements"].update(changes)
            with self.subTest(changes=changes), self.assertRaises(gate.Refused):
                self.check(value)

    def test_malformed_profile(self):
        for value in [[], {**self.profile, "Entitlements": []}]:
            with self.subTest(value=value), self.assertRaises(gate.Refused):
                self.check(value)

    def test_native_module_refuses_catalyst_only_identity(self):
        signed = dict(self.profile["Entitlements"])
        signed["com.apple.security.app-sandbox"] = True
        gate.check_profile_authorization(self.profile, signed)
        signed["application-identifier"] = self.team + "." + self.identifier
        with self.assertRaises(gate.Refused):
            gate.check_profile_authorization(self.profile, signed)

    def test_signed_identity_must_match_profile(self):
        signed = {"com.apple.application-identifier": "OTHERTEAM1.invalid"}
        with self.assertRaises(gate.Refused):
            gate.check_profile_authorization(self.profile, signed)


if __name__ == "__main__":
    unittest.main()
