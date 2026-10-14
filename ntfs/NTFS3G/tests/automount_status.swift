// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only mount identity check before the automount gate writes test files.
import Foundation
import Darwin

precondition(CommandLine.arguments.count == 3)
let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
precondition(root.lastPathComponent == "mount" && root.deletingLastPathComponent().lastPathComponent.hasPrefix("fskit-fixture."))
var fs = statfs()
guard statfs(root.path, &fs) == 0 else { exit(1) }
func cString<T>(_ value: inout T) -> String {
    withUnsafePointer(to: &value) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
    }
}
let kind = cString(&fs.f_fstypename)
let device = cString(&fs.f_mntfromname)
let mount = URL(fileURLWithPath: cString(&fs.f_mntonname)).resolvingSymlinksInPath()
print("AUTOMOUNT_OBSERVED type=\(kind) device=\(device) mount=\(mount.path) readonly=\((fs.f_flags & UInt32(MNT_RDONLY)) != 0)")
guard mount == root, device == CommandLine.arguments[2], kind == "openntfs",
      (fs.f_flags & UInt32(MNT_RDONLY)) == 0 else { exit(2) }
