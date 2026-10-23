#!/usr/bin/env python3
"""Read-only public NTFS distribution gate. Never strip the driver to pass.

Accepts an already exported, signed and stapled Release app. No signing,
registration, mounting, profile generation or account changes are performed.
"""
import datetime
import pathlib
import plistlib
import re
import subprocess
import sys


class Refused(Exception):
    pass


def require(value, reason):
    if not value:
        raise Refused(reason)


def run(*arguments):
    result = subprocess.run(arguments, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=90, check=False)
    operation = pathlib.Path(arguments[0]).name
    if len(arguments) > 1 and arguments[1] in ("stapler", "cms"):
        operation += " " + arguments[1]
    require(result.returncode == 0, "Required validation failed: " + operation)
    return result.stdout, result.stderr


def check_profile(profile, identifier, team, fskit=False):
    """CMS-decoded metadata only; never print device lists or profile bytes."""
    require(isinstance(profile, dict), "Invalid distribution profile")
    require("ProvisionedDevices" not in profile,
            "Device-bound development profile cannot be publicly distributed")
    require(profile.get("ProvisionsAllDevices") is True,
            "An unrestricted Developer ID distribution profile is required")
    require(profile.get("TeamIdentifier") == [team], "Profile team mismatch")
    expires = profile.get("ExpirationDate")
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    require(isinstance(expires, datetime.datetime) and expires.replace(tzinfo=None) > now,
            "Distribution profile missing or expired")
    entitlements = profile.get("Entitlements", {})
    require(isinstance(entitlements, dict), "Invalid profile entitlements")
    require(not entitlements.get("get-task-allow") and
            not entitlements.get("com.apple.security.get-task-allow"),
            "Distribution profile enables debugging")
    application = entitlements.get("com.apple.application-identifier",
                                   entitlements.get("application-identifier"))
    require(application == team + "." + identifier, "Profile app identity mismatch")
    if fskit:
        require(entitlements.get("com.apple.developer.fskit.fsmodule") is True,
                "Distribution profile does not authorize FSKit")


def check_profile_authorization(profile, signed_entitlements):
    """taskgated enforces each restricted identity, even after notarization."""
    allowed = profile.get("Entitlements", {})
    for key in ("application-identifier", "com.apple.application-identifier",
                "com.apple.developer.team-identifier", "com.apple.developer.fskit.fsmodule"):
        if key in signed_entitlements:
            require(key in allowed and signed_entitlements[key] == allowed[key],
                    "Signed restricted entitlement not authorized by profile: " + key)


def check(app):
    require(app.is_dir() and not app.is_symlink(), "Expected a real app directory")
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == "com.github.niklaus85.OpenCommander",
            "Unexpected app identity")
    require(not (contents / "MacOS/OpenCommander.debug.dylib").exists(),
            "Export a Release build, not the local Debug installation")
    extension = contents / "Extensions/OpenCommanderNTFSModule.appex"
    required = [app, extension,
                contents / "MacOS/OpenCommanderNTFSAccess",
                contents / "PlugIns/OpenCommanderMacBridge.bundle",
                contents / "MacOS/OpenCommanderCloudArguments",
                contents / "MacOS/OpenCommanderSSHAskPass"]
    team = None
    for item in required:
        require(item.exists() and not item.is_symlink(), "Required NTFS/app component missing")
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(item))
        out, err = run("/usr/bin/codesign", "-d", "--verbose=4", str(item))
        metadata = (out + err).decode("utf-8", errors="replace")
        require("Authority=Developer ID Application:" in metadata,
                "A Developer ID Application signature is required on every code component")
        match = re.search(r"^TeamIdentifier=([A-Z0-9]{10})$", metadata, re.MULTILINE)
        require(match is not None, "Signed team missing")
        if team is None:
            team = match.group(1)
        require(match.group(1) == team, "Components signed by different teams")
        require("(runtime)" in metadata, "Hardened runtime missing")
        signed, _ = run("/usr/bin/codesign", "-d", "--entitlements", ":-", str(item))
        entitlements = plistlib.loads(signed) if signed.strip() else {}
        require(not entitlements.get("get-task-allow") and
                not entitlements.get("com.apple.security.get-task-allow"),
                "Code signature enables development debugging")
        if item == extension:
            require(entitlements.get("com.apple.security.app-sandbox") is True and
                    entitlements.get("com.apple.developer.fskit.fsmodule") is True,
                    "Required signed FSKit/sandbox entitlement missing")
    extension_info = plistlib.loads((extension / "Contents/Info.plist").read_bytes())
    module_id = extension_info.get("CFBundleIdentifier")
    require(module_id in ("com.github.niklaus85.OpenCommander.NTFSModule",
                          "com.github.niklaus85.OpenCommander.NTFSModuleV2"),
            "Unexpected NTFS module identity")
    require(extension_info.get("OpenCommanderNTFSWriteCondition") ==
            "OPENCOMMANDER_NTFS3G_EXPERIMENTAL", "Writable NTFS engine not enabled")
    daemon = contents / "Library/LaunchDaemons/com.github.niklaus85.OpenCommander.NTFSAccess.plist"
    require(daemon.is_file(), "Permanent authorization helper configuration missing")
    for bundle, identifier, fskit in [(app, info["CFBundleIdentifier"], False),
                                     (extension, module_id, True)]:
        profile = bundle / "Contents/embedded.provisionprofile"
        require(profile.is_file() and not profile.is_symlink(),
                "Expected Developer ID provisioning profile missing")
        decoded, _ = run("/usr/bin/security", "cms", "-D", "-i", str(profile))
        profile_data = plistlib.loads(decoded)
        check_profile(profile_data, identifier, team, fskit)
        signed, _ = run("/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle))
        check_profile_authorization(profile_data, plistlib.loads(signed) if signed.strip() else {})
    run("/usr/bin/xcrun", "stapler", "validate", str(app))
    run("/usr/sbin/spctl", "--assess", "--type", "execute", str(app))
    print("PASS complete NTFS app: Developer ID, distribution profiles, helper, writable FSKit, stapled notarization and Gatekeeper")


if __name__ == "__main__":
    try:
        require(len(sys.argv) == 2, "Usage: check-macos-ntfs-distribution.py /path/OpenCommander.app")
        # stapler resolves relative bundle paths differently from codesign.
        # Keep the explicit input symlink refusal before canonicalizing.
        supplied = pathlib.Path(sys.argv[1])
        require(not supplied.is_symlink(), "Expected a real app directory")
        check(supplied.resolve())
    except (Refused, OSError, ValueError, plistlib.InvalidFileException,
            subprocess.TimeoutExpired) as error:
        print("REFUSED:", str(error) if isinstance(error, Refused) else "Cannot validate distribution inputs", file=sys.stderr)
        sys.exit(1)
