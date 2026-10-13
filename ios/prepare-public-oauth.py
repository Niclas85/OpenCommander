#!/usr/bin/env python3
"""Package only explicitly provided publisher desktop identities, never tokens."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

def package(destination, environment):
    source = Path(__file__).resolve().parents[1] / "linux/opencommander/public_oauth.py"
    spec = importlib.util.spec_from_file_location("public_oauth_schema", source)
    schema = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(schema)
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    prepared = {}
    for kind, name in (("drive", "google"), ("onedrive", "onedrive"), ("dropbox", "dropbox")):
        path = environment.get("OPENCOMMANDER_" + name.upper() + "_OAUTH_FILE", "")
        if not path:
            continue
        with Path(path).open("rb") as handle:
            raw = handle.read(16385)
        if len(raw) > 16384:
            raise ValueError("desktop identity exceeds limit")
        value = json.loads(raw)
        if kind == "drive":
            if not isinstance(value, dict) or set(value) != {"installed"}:
                raise ValueError("installed-desktop export required")
            value = schema.normalized(value)
        else:
            value = schema.normalized_native(kind, value)
        prepared[name] = (json.dumps(value, sort_keys=True) + "\n").encode()
    # Validate every identity before altering the generated bundle resources.
    # Rebuild without opt-in removes stale app identities, not user configuration.
    for name in ("google", "onedrive", "dropbox"):
        target = destination / (name + "-oauth.json")
        if name not in prepared:
            target.unlink(missing_ok=True)
            continue
        descriptor, temporary = tempfile.mkstemp(prefix="oauth-", dir=destination)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(prepared[name]); handle.flush(); os.fsync(handle.fileno())
            os.replace(temporary, target)
        finally:
            Path(temporary).unlink(missing_ok=True)

if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("resource directory required")
        package(sys.argv[1], os.environ)
    except (OSError, ValueError, TypeError):
        # No paths, raw values, account credentials or parsing snippets in logs.
        raise SystemExit("Invalid publisher desktop OAuth configuration / Ungültige Desktop-OAuth-Konfiguration")
