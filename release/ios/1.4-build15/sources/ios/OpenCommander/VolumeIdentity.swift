import Foundation
import Darwin
#if os(macOS)
import DiskArbitration
#endif

/// Mount-session UUIDs can change for FSKit NTFS. Prefer a read-only NTFS boot
/// serial/geometry identity, or the kernel's stable partition UUID when available.
/// No raw writes, mounts, elevation, scans of other disks or shell commands.
enum VolumeIdentity {
    static func token(at url: URL) throws -> String? {
#if targetEnvironment(macCatalyst)
        if let identity = DesktopBridge.shared?.stableVolumeIdentity(url) { return identity }
#elseif os(macOS)
        if let identity = nativeToken(at: url) { return identity }
#endif
        return try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
    static func matches(_ expected: String, at url: URL) throws -> Bool {
        if expected.hasPrefix("ntfs:") || expected.hasPrefix("partition:") { return try token(at: url) == expected }
        // Version-one checkpoints stored the reported UUID. Never silently
        // adopt a changed identity when the older record cannot prove equivalence.
        return try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString == expected
    }
#if os(macOS)
    static func nativeToken(at url: URL) -> String? {
        var filesystem = statfs()
        guard statfs(url.path, &filesystem) == 0 else { return nil }
        func string<T>(_ value: inout T) -> String {
            withUnsafePointer(to: &value) { $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) } }
        }
        let type = string(&filesystem.f_fstypename).lowercased()
        let format = (try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]).volumeLocalizedFormatDescription)?.lowercased() ?? ""
        guard ["openntfs", "ntfs"].contains(type) || format.contains("openntfs") else { return nil }
        var device = string(&filesystem.f_mntfromname)
        if device.range(of: #"^/dev/(?:r)?disk[0-9]+(?:s[0-9]+)*$"#, options: .regularExpression) != nil,
           let boot = bootToken(device: device) { return boot }
        let mount = URL(fileURLWithPath: string(&filesystem.f_mntonname), isDirectory: true)
        // FSKit may hold the raw device exclusively. NTFS exposes the same boot
        // sector through its reserved, regular $Boot metadata stream.
        if let boot = readBoot(path: mount.appendingPathComponent("$Boot").path, regular: true) { return boot }
        if let session = DASessionCreate(kCFAllocatorDefault),
           let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, mount as CFURL),
           let description = DADiskCopyDescription(disk) as NSDictionary?,
           let name = DADiskGetBSDName(disk) {
            device = "/dev/" + String(cString: name)
            if device.range(of: #"^/dev/disk[0-9]+(?:s[0-9]+)*$"#, options: .regularExpression) != nil,
                let boot = bootToken(device: device) { return boot }
            guard let value = description.object(forKey: kDADiskDescriptionMediaUUIDKey) else { return nil }
            let reference = value as CFTypeRef
            if CFGetTypeID(reference) == CFUUIDGetTypeID() {
                let uuid = unsafeBitCast(reference, to: CFUUID.self)
                if let text = CFUUIDCreateString(kCFAllocatorDefault, uuid) {
                    return "partition:" + (text as String)
                }
            }
        }
        return nil
    }
    private static func bootToken(device: String) -> String? {
        readBoot(path: device, regular: false)
    }
    private static func readBoot(path: String, regular: Bool) -> String? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
            (regular ? info.st_mode & S_IFMT == S_IFREG && info.st_size >= 512 : [S_IFBLK, S_IFCHR].contains(info.st_mode & S_IFMT)) else { return nil }
        var data = Data(count: 512)
        let count = data.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, 0) }
        guard count == 512 else { return nil }
        return ntfsBootToken(data)
    }
#endif
    static func ntfsBootToken(_ data: Data) -> String? {
        let bytes = Array(data)
        guard bytes.count == 512, Array(bytes[3..<11]) == Array("NTFS    ".utf8), bytes[510] == 0x55, bytes[511] == 0xaa else { return nil }
        func little(_ offset: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(0) { $0 | UInt64(bytes[offset + $1]) << ($1 * 8) }
        }
        let sector = little(11, 2), cluster = UInt64(bytes[13]), sectors = little(40, 8), serial = little(72, 8)
        guard [512, 1024, 2048, 4096].contains(sector), cluster > 0, cluster <= 128,
            cluster & (cluster - 1) == 0, sectors >= 1024, sectors <= UInt64(Int64.max) / sector, serial != 0 else { return nil }
        return "ntfs:" + String(format: "%016llX", serial) + ":\(sector):\(sectors)"
    }
}
