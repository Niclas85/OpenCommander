// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only checks through the same public Security framework used for code identity.
import Foundation
import Security

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(7)
}
let diagnostic = CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--diagnostic"
guard diagnostic || CommandLine.arguments.count == 2 else { fail("Expected [--diagnostic] extension bundle path") }
let allowed = diagnostic ? ["com.github.niklaus85.OpenCommander.NTFSStartTest.NTFSModule"] :
    ["com.github.niklaus85.OpenCommander.NTFSModule", "com.github.niklaus85.OpenCommander.NTFSModuleV2"]
let url = URL(fileURLWithPath: CommandLine.arguments[diagnostic ? 2 : 1])
var code: SecStaticCode?
var result = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code)
guard result == errSecSuccess, let code else { fail("Cannot inspect extension identity: \(result)") }
result = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil)
guard result == errSecSuccess else { fail("Extension signature validation failed: \(result)") }
var dictionary: CFDictionary?
result = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &dictionary)
guard result == errSecSuccess, let info = dictionary as? [String: Any] else {
    fail("Cannot inspect signed extension identity: \(result)")
}
let identifier = info[kSecCodeInfoIdentifier as String] as? String ?? ""
guard allowed.contains(identifier) else {
    fail("Unexpected extension identifier: \(identifier)")
}
guard let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else {
    fail("Extension has no signed entitlement dictionary")
}
for key in ["com.apple.security.app-sandbox", "com.apple.developer.fskit.fsmodule"] {
    guard let number = entitlements[key] as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID(), number.boolValue else {
        fail("Required signed Boolean entitlement missing/false: \(key). No image should be created.")
    }
}
print("PASS Security framework: valid extension signature, exact identity, sandbox=true, FSKit=true")
