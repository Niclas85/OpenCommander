import Foundation
import Darwin

@main struct ProfileHolder {
static func main() throws {
guard CommandLine.arguments.count == 2, let canonical = realpath(CommandLine.arguments[1],nil) else { fatalError("existing isolated root required") }
defer { free(canonical) }
let root = URL(fileURLWithPath:String(cString:canonical)), fm = FileManager.default
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-ProfileGuard-20261023-"),
      fm.fileExists(atPath:root.appendingPathComponent("Left").path),
      fm.fileExists(atPath:root.appendingPathComponent("Right").path) else { fatalError("unsafe profile holder") }
let lease = try CommanderProfileLease(directory:root)
try Data("ready".utf8).write(to:root.appendingPathComponent("LeaseReady.txt"),options:.withoutOverwriting)
print("HOLDING_OWN_TEST_PROFILE_PID \(getpid())")
fflush(stdout)
withExtendedLifetime(lease) { while true { pause() } }
}
}
