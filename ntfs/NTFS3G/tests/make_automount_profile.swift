// SPDX-License-Identifier: GPL-2.0-or-later
// Generates a developer-only build artifact. Ordinary/release metadata stays unchanged.
import Foundation

precondition(CommandLine.arguments.count == 3)
let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let target = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
precondition(source.lastPathComponent == "Info.plist" && target.lastPathComponent == "Automount-Info.plist")
precondition(target.path.contains("/ntfs/NTFS3G/.build-native/"))
var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: source), format: nil) as! [String: Any]
var attributes = plist["EXAppExtensionAttributes"] as! [String: Any]
precondition((attributes["FSMediaTypes"] as! [String: Any]).isEmpty)
// Probe before Apple's NTFS reader. GPT Basic Data also includes exFAT:
// the boot-sector parser and read-only safety inspection must reject it.
func media(_ properties: [String: Any], order: Int) -> [String: Any] {
    ["FSMediaProperties": properties, "FSProbeOrder": order]
}
attributes["FSMediaTypes"] = [
    "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7": media([
        "Content Hint": "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7", "Leaf": true
    ], order: 1900),
    "Windows_NTFS": media(["Content Hint": "Windows_NTFS", "Leaf": true], order: 900),
    "Partitionless": media(["Leaf": true, "Whole": true], order: 3900)
]
plist["EXAppExtensionAttributes"] = attributes
plist["OpenCommanderNTFSAutomaticMounting"] = true
let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try data.write(to: target, options: .atomic)
print("Generated opt-in automount profile; this is not installation or mount approval.")
