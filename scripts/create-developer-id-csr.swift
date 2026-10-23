// Generates only a PUBLIC PKCS#10 request. The private key stays
// in the existing login keychain. No unlocking, password handling or UI prompts.
import Foundation
import Security

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
guard CommandLine.arguments.count == 3 else { fail("Usage: create-developer-id-csr.swift /new/request.certSigningRequest contact-email") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let email = CommandLine.arguments[2]
guard destination.path.hasPrefix("/Users/niklaus/Documents/OpenCommander/ntfs/NTFS3G/.build-native/"),
      !FileManager.default.fileExists(atPath: destination.path),
      email.utf8.allSatisfy({ $0 > 32 && $0 < 127 }), email.contains("@") else {
    fail("Expected new private-workspace CSR path and ASCII contact email")
}
guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else {
    fail("Cannot disable authentication UI for this process")
}
let tag = Data("com.github.niklaus85.OpenCommander.developer-id.20261023".utf8)
let query: [String: Any] = [kSecClass as String: kSecClassKey,
    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
    kSecAttrApplicationTag as String: tag, kSecReturnRef as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne]
var found: CFTypeRef?
let lookup = SecItemCopyMatching(query as CFDictionary, &found)
let key: SecKey
if lookup == errSecSuccess, let found {
    guard CFGetTypeID(found) == SecKeyGetTypeID() else { fail("Unexpected keychain object") }
    key = (found as! SecKey)
    print("Using the existing dedicated Developer ID key")
} else {
    guard lookup == errSecItemNotFound else { fail("Keychain access requires user intervention (\(lookup))") }
    var error: Unmanaged<CFError>?
    let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits as String: 2048,
        kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
            kSecAttrLabel as String: "OpenCommander Developer ID 2026-10-23",
            kSecAttrIsExtractable as String: false]]
    guard let created = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
        fail("Cannot create key without user intervention (\(code)); no unlock attempted")
    }
    key = created
    print("Created dedicated RSA key in the existing keychain; private key not exported")
}
func tlv(_ tag: UInt8, _ value: Data) -> Data {
    var length = value.count, encoded = Data()
    if length < 128 { encoded.append(UInt8(length)) }
    else {
        var bytes: [UInt8] = []
        while length > 0 { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 }
        encoded.append(0x80 | UInt8(bytes.count)); encoded.append(contentsOf: bytes)
    }
    return Data([tag]) + encoded + value
}
func sequence(_ value: Data) -> Data { tlv(0x30, value) }
func attribute(_ oid: [UInt8], _ value: String, _ type: UInt8) -> Data {
    tlv(0x31, sequence(tlv(0x06, Data(oid)) + tlv(type, Data(value.utf8))))
}
var error: Unmanaged<CFError>?
guard let publicKey = SecKeyCopyPublicKey(key),
      let publicBytes = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
    fail("Cannot export public key; private key remains in keychain")
}
let rsa = sequence(tlv(0x06, Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01])) + Data([0x05,0x00]))
let sha256RSA = sequence(tlv(0x06, Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b])) + Data([0x05,0x00]))
let subject = sequence(attribute([0x55,0x04,0x03], "OpenCommander Developer ID 2026-10-23", 0x0c) +
    attribute([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x09,0x01], email, 0x16))
let publicInfo = sequence(rsa + tlv(0x03, Data([0]) + publicBytes))
let requestInfo = sequence(Data([0x02,0x01,0x00]) + subject + publicInfo + Data([0xa0,0x00]))
guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                          requestInfo as CFData, &error) as Data? else {
    fail("Keychain signing requires user intervention; no authentication bypass attempted")
}
let der = sequence(requestInfo + sha256RSA + tlv(0x03, Data([0]) + signature))
let body = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
let pem = "-----BEGIN CERTIFICATE REQUEST-----\n" + body + "\n-----END CERTIFICATE REQUEST-----\n"
do {
    try Data(pem.utf8).write(to: destination, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
} catch { fail("Cannot save new public CSR; private key remains in keychain") }
print("PUBLIC_CSR_CREATED \(destination.path)")
