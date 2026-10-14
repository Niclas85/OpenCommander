// SPDX-License-Identifier: GPL-2.0-or-later
// Bounds one explicitly launched test command, never a system daemon or another app.
import Foundation
import Darwin

guard CommandLine.arguments.count >= 3,
      let seconds = Int(CommandLine.arguments[1]), (1...120).contains(seconds),
      CommandLine.arguments[2].hasPrefix("/") else {
    fputs("Usage: run_bounded.swift seconds /absolute/test-command [args...]\n", stderr)
    exit(64)
}
let process = Process()
process.executableURL = URL(fileURLWithPath: CommandLine.arguments[2])
process.arguments = Array(CommandLine.arguments.dropFirst(3))
let completed = DispatchSemaphore(value: 0)
process.terminationHandler = { _ in completed.signal() }
do { try process.run() }
catch { fputs("Could not launch test command: \(error)\n", stderr); exit(126) }
if completed.wait(timeout: .now() + .seconds(seconds)) == .timedOut {
    fputs("TEST_TIMEOUT: test command exceeded \(seconds)s; no system service will be restarted.\n", stderr)
    if process.isRunning { process.terminate() }
    if completed.wait(timeout: .now() + .seconds(3)) == .timedOut, process.isRunning {
        // Only the direct child created above, not a name-based process search.
        _ = kill(process.processIdentifier, SIGKILL)
        _ = completed.wait(timeout: .now() + .seconds(3))
    }
    exit(124)
}
exit(process.terminationReason == .exit ? process.terminationStatus : 128 + process.terminationStatus)
