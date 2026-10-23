// Scoped authorization for the NEW OpenCommander signing key only.
// Does not unlock keychains, handle passwords, change partitions or allow all apps.
import Foundation
import Security
import CryptoKit

func stop(_ reason: String, _ status: OSStatus = errSecSuccess) -> Never {
    FileHandle.standardError.write(Data(("REFUSED: \(reason) [\(status)]\n").utf8)); exit(1)
}
let grant = CommandLine.arguments == [CommandLine.arguments[0], "--grant-codesign"]
guard grant || CommandLine.arguments.count == 1 else { stop("Expected no argument or explicit --grant-codesign") }
guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { stop("Cannot forbid authentication UI for this process") }
let tag = Data("com.github.niklaus85.OpenCommander.developer-id.20261023".utf8)
let query: [String: Any] = [kSecClass as String: kSecClassKey,
    kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
    kSecAttrApplicationTag as String: tag,
    kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
var result: CFTypeRef?
let lookup = SecItemCopyMatching(query as CFDictionary, &result)
guard lookup == errSecSuccess, let result, CFGetTypeID(result) == SecKeyGetTypeID() else { stop("Dedicated key unavailable", lookup) }
let key = result as! SecKey
var attributeQuery = query
attributeQuery.removeValue(forKey: kSecReturnRef as String)
attributeQuery[kSecReturnAttributes as String] = true
var itemAttributes: CFTypeRef?
let attributeStatus = SecItemCopyMatching(attributeQuery as CFDictionary, &itemAttributes)
guard attributeStatus == errSecSuccess, let stored = itemAttributes as? [String:Any] else { stop("Cannot check dedicated item metadata", attributeStatus) }
guard stored[kSecAttrLabel as String] as? String == "OpenCommander Developer ID 2026-10-23" else { stop("Wrong key label") }
let certificateURL = URL(fileURLWithPath: "/Users/niklaus/Downloads/developerID_application.cer")
guard let certificateData = try? Data(contentsOf: certificateURL),
      Insecure.SHA1.hash(data: certificateData).map({ String(format: "%02X", $0) }).joined() == "F1E94882CE21B463C2243767E8BEC333A51FEFCB",
      let certificate = SecCertificateCreateWithData(nil, certificateData as CFData),
      let certificateKey = SecCertificateCopyKey(certificate),
      let publicKey = SecKeyCopyPublicKey(key) else { stop("Exact new Developer ID certificate unavailable") }
var error: Unmanaged<CFError>?
guard let expectedPublic = SecKeyCopyExternalRepresentation(certificateKey, &error) as Data?,
      let actualPublic = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
      expectedPublic == actualPublic else { stop("Certificate does not match dedicated key") }

// This is a legacy login-keychain SecKey; public keychain item APIs take its item reference.
let item = unsafeBitCast(key, to: SecKeychainItem.self)
var access: SecAccess?
let copied = SecKeychainItemCopyAccess(item, &access)
guard copied == errSecSuccess, let access else { stop("Cannot inspect own key access", copied) }
var list: CFArray?
let listed = SecAccessCopyACLList(access, &list)
guard listed == errSecSuccess, let acls = list as? [SecACL] else { stop("Cannot inspect own ACL", listed) }
var trusted: SecTrustedApplication?
let trustedStatus = SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &trusted)
guard trustedStatus == errSecSuccess, let trusted else { stop("Cannot identify Apple codesign", trustedStatus) }
var trustedData: CFData?
guard SecTrustedApplicationCopyData(trusted, &trustedData) == errSecSuccess, let trustedData else { stop("Cannot compare trusted application") }
var signPrompt: SecKeychainPromptSelector?
var alreadyGranted = false
for acl in acls {
    let authorizations = SecACLCopyAuthorizations(acl) as NSArray
    guard authorizations.contains(kSecACLAuthorizationSign as String) else { continue }
    var applications: CFArray?, description: CFString?
    var prompt = SecKeychainPromptSelector()
    guard SecACLCopyContents(acl, &applications, &description, &prompt) == errSecSuccess else { continue }
    signPrompt = prompt
    if authorizations.count == 1, let apps = applications as? [SecTrustedApplication], apps.count == 1 {
        var data: CFData?
        if SecTrustedApplicationCopyData(apps[0], &data) == errSecSuccess,
           let data, (data as Data) == (trustedData as Data) { alreadyGranted = true }
    }
}
print("PASS exact dedicated key matches new certificate; inspected only this item's ACL; no private key exported")
if alreadyGranted { print("PASS codesign-only signing ACL already present; no change"); exit(0) }
guard grant else { print("READ_ONLY: codesign-only signing ACL not yet present"); exit(0) }
guard let prompt = signPrompt else { stop("No simple signing ACL to preserve prompt policy") }
var added: SecACL?
let created = SecACLCreateWithSimpleContents(access, [trusted] as CFArray,
    "OpenCommander Developer ID signing" as CFString, prompt, &added)
guard created == errSecSuccess, let added else { stop("Cannot prepare scoped ACL", created) }
let narrowed = SecACLUpdateAuthorizations(added, [kSecACLAuthorizationSign] as CFArray)
guard narrowed == errSecSuccess else { stop("Cannot restrict ACL to signing", narrowed) }
let saved = SecKeychainItemSetAccess(item, access)
guard saved == errSecSuccess else { stop("macOS requires user authorization; no unlock or password attempted", saved) }
print("APPLIED: codesign-only signing ACL to exact new key; existing ACLs and prompt policy retained; no partition changes")
