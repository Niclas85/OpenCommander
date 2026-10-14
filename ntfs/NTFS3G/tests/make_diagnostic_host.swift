// SPDX-License-Identifier: GPL-2.0-or-later
// Generate only development metadata; never advertise folder/URL handling for the test host.
import Foundation

precondition(CommandLine.arguments.count == 3)
let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let target = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
precondition(source.lastPathComponent == "Info.plist")
precondition(target.lastPathComponent == "Host-Info.plist" && target.path.contains("/ntfs/NTFS3G/.build-native/"))
var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: source), format: nil) as! [String: Any]
plist.removeValue(forKey: "CFBundleDocumentTypes")
plist.removeValue(forKey: "CFBundleURLTypes")
plist["CFBundleDisplayName"] = "OpenCommander NTFS Starttest"
plist["OpenCommanderNTFSLaunchDiagnostic"] = true
let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try output.write(to: target, options: .atomic)
print("PASS diagnostic host metadata: no document/URL registration; original Info.plist unchanged")
