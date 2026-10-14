import Foundation

let uuid = "005C1A70-98E8-48E6-8809-334901DC6E32"
let disk = "disk4s1"
precondition(!NTFSAccessPolicy.isMounted([:]))
precondition(!NTFSAccessPolicy.isMounted(["MountPoint": ""]))
precondition(NTFSAccessPolicy.isMounted(["MountPoint": "/Volumes/Elements"]))
let executable = try NTFSAccessPolicy.executableURL()
precondition(FileManager.default.isExecutableFile(atPath: executable.path))
let valid: [String: Any] = ["DeviceIdentifier": disk, "DiskUUID": uuid,
    "Internal": false, "WholeDisk": false, "WritableMedia": true,
    "BusProtocol": "USB", "Content": "Microsoft Basic Data", "IOKitSize": UInt64(5_000_945_205_248)]
precondition(NTFSAccessPolicy.eligible(valid, device: disk, uuid: uuid))
for device in ["disk4", "/dev/disk4s1", "../disk4s1", "disk4s1;id", "disk4s1\n", "disk4s1s1", "", "disk-1s1"] {
    precondition(!NTFSAccessPolicy.validDevice(device))
    precondition(!NTFSAccessPolicy.eligible(valid, device: device, uuid: uuid))
}
precondition(!NTFSAccessPolicy.eligible(valid, device: disk, uuid: UUID().uuidString))
for (key, value) in [("Internal", true as Any), ("WholeDisk", true), ("WritableMedia", false),
                     ("BusProtocol", "Disk Image"), ("Content", "Apple_APFS"), ("IOKitSize", UInt64(512))] {
    var changed = valid; changed[key] = value
    precondition(!NTFSAccessPolicy.eligible(changed, device: disk, uuid: uuid))
}
for key in valid.keys {
    var missing = valid; missing.removeValue(forKey: key)
    precondition(!NTFSAccessPolicy.eligible(missing, device: disk, uuid: uuid))
}
let output = try NTFSAccessPolicy.run("/usr/bin/printf", ["test-output"])
precondition(String(data: output, encoding: .utf8) == "test-output")
do { _ = try NTFSAccessPolicy.run("/usr/bin/false", []); fatalError("Nonzero status accepted") } catch {}
do { _ = try NTFSAccessPolicy.run("/bin/sleep", ["2"], timeout: 0.05); fatalError("Timeout accepted") } catch {}
print("PASS NTFS access policy: external USB partition only; internal/whole/image/non-NTFS/readonly/missing/mismatched identities refused")
print("PASS NTFS command boundary: exact output, nonzero exit and bounded timeout")
