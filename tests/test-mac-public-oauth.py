#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_mac_oauth", root / "ios/prepare-public-oauth.py")
packager = importlib.util.module_from_spec(spec); spec.loader.exec_module(packager)
with tempfile.TemporaryDirectory(prefix="OpenCommander-Publisher-Test-") as temporary:
    directory = Path(temporary)
    resources = directory / "Resources"
    microsoft = directory / "microsoft.json"
    microsoft.write_text(json.dumps({"client_id": "00000000-1111-2222-3333-444444444444", "flow": "pkce"}))
    google = directory / "google.json"
    google.write_text(json.dumps({"installed": {"client_id": "synthetic.apps.googleusercontent.com", "client_secret": "synthetic-desktop"}}))
    environment = {"OPENCOMMANDER_ONEDRIVE_OAUTH_FILE": str(microsoft), "OPENCOMMANDER_GOOGLE_OAUTH_FILE": str(google)}
    packager.package(resources, environment)
    assert set(json.loads((resources / "onedrive-oauth.json").read_text())) == {"client_id", "flow"}
    assert set(json.loads((resources / "google-oauth.json").read_text())) == {"client_id", "client_secret"}
    assert (resources / "google-oauth.json").stat().st_mode & 0o777 == 0o600
    previous = (resources / "onedrive-oauth.json").read_bytes()
    microsoft.write_text(json.dumps({"client_id": "00000000-1111-2222-3333-444444444444", "flow": "pkce", "token": "SYNTHETIC_USER_TOKEN"}))
    try:
        packager.package(resources, environment)
        raise AssertionError("account token packaged")
    except ValueError:
        pass
    assert (resources / "onedrive-oauth.json").read_bytes() == previous
    microsoft.write_bytes(b"x" * 16385)
    try:
        packager.package(resources, environment)
        raise AssertionError("oversized identity packaged")
    except ValueError:
        pass
    packager.package(resources, {})
    assert not list(resources.glob("*-oauth.json")), "stale publisher identity retained on rebuild"
print("PASS Mac publisher packaging: shared Linux schema, no account tokens, private resources, all-input preflight, bounded input and stale-resource removal")
