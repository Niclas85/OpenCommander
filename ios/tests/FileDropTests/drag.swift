// Manual UI test driver for a new synthetic fixture, never user documents.
// Coordinates must be obtained from the current UI before each invocation.
import Foundation
import CoreGraphics
import AppKit

if CommandLine.arguments == [CommandLine.arguments[0], "--inspect"] {
    let allowed = Set(["com.github.niklaus85.OpenCommander", "com.github.niklaus85.OpenCommander.MacUITests", "com.apple.finder", "com.apple.TextEdit", "com.apple.Preview", "com.apple.Safari", "com.google.Chrome"])
    let pids = Set(NSWorkspace.shared.runningApplications.filter { allowed.contains($0.bundleIdentifier ?? "") }.map(\.processIdentifier))
    let visibleWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    print("FRONT_APP", NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
    for (order, window) in visibleWindows.enumerated() {
        if let pid = window[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
           window[kCGWindowLayer as String] as? Int == 0 {
            if ["com.apple.finder", "com.apple.TextEdit", "com.apple.Preview", "com.apple.Safari", "com.google.Chrome"].contains(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""),
               !(window[kCGWindowName as String] as? String ?? "").contains("OpenCommander-MacUITest-") { continue }
            print("TEST_WINDOW", pid, "stack=\(order)", window[kCGWindowBounds as String] ?? "unknown")
        }
    }
    exit(0)
}

guard (5...10).contains(CommandLine.arguments.count),
      let sx = Double(CommandLine.arguments[1]), let sy = Double(CommandLine.arguments[2]),
      let dx = Double(CommandLine.arguments[3]), let dy = Double(CommandLine.arguments[4]) else {
    fatalError("Usage: drag sourceX sourceY destinationX destinationY [--cancel|--hover|--finder-source|--finder-target|--finder-window] [--option] [--command]")
}
let arguments = Array(CommandLine.arguments.dropFirst(5))
let modifiers = arguments.filter { ["--option", "--command"].contains($0) }
let behaviours = arguments.filter { ["--cancel", "--hover"].contains($0) }
let modes = arguments.filter { !["--option", "--command", "--cancel", "--hover"].contains($0) }
guard modes.count <= 1, Set(modifiers).count == modifiers.count else { fatalError("Duplicate drag options") }
let option = modes.first ?? ""
let cancel = behaviours.contains("--cancel")
guard Set(behaviours).count == behaviours.count,
      ["", "--scroll-right", "--scroll-left", "--app-window", "--finder-source", "--finder-target", "--finder-window", "--finder-preview-target", "--textedit-source", "--textedit-target", "--textedit-window", "--preview-source", "--preview-target", "--preview-window", "--safari-source", "--chrome-source"].contains(option) else { fatalError("Unknown option") }
guard CGPreflightPostEventAccess() else { fatalError("UI event posting is not authorized") }
// Explicit opt-in for live acceptance of the installed build. Never default to it.
let installedFixture = ProcessInfo.processInfo.environment["OPENCOMMANDER_DRAG_TEST_FIXTURE"]
if let fixture = installedFixture {
    guard fixture.hasPrefix("/Users/niklaus/Documents/OpenCommander/ntfs/NTFS3G/.build-native/google-live-"),
          FileManager.default.fileExists(atPath: fixture + "/Quelle/Prüfung.txt"),
          FileManager.default.fileExists(atPath: fixture + "/FinderExport") else {
        fatalError("Installed-app acceptance requires the existing synthetic fixture")
    }
}
let testID = installedFixture == nil ? "com.github.niklaus85.OpenCommander.MacUITests" : "com.github.niklaus85.OpenCommander"
guard let testApp = NSRunningApplication.runningApplications(withBundleIdentifier: testID).first else {
    fatalError("The isolated test app must be running")
}
let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
guard !option.hasPrefix("--finder-") || finder != nil else { fatalError("Finder must already be running") }
let externalID = option == "--safari-source" ? "com.apple.Safari" : option == "--chrome-source" ? "com.google.Chrome" : option.hasPrefix("--textedit-") ? "com.apple.TextEdit" : option.hasPrefix("--preview-") || option == "--finder-preview-target" ? "com.apple.Preview" : "com.apple.finder"
let external = NSRunningApplication.runningApplications(withBundleIdentifier: externalID).first
guard option.isEmpty || external != nil else { fatalError("The named fixture app must already be running") }
let externalSource = option.hasSuffix("-source") || option == "--finder-preview-target"
let externalTarget = option.hasSuffix("-target")
let windowMove = option.hasSuffix("-window")
let app = option == "--finder-preview-target" ? finder! : option == "--app-window" ? testApp : externalSource || windowMove ? external! : testApp
let destinationApp = option == "--app-window" ? testApp : externalTarget || windowMove ? external! : testApp
// Put the intended destination immediately behind the source, rather than
// accidentally leaving the caller/chat window behind the Finder fixture.
if externalSource || externalTarget {
    destinationApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    let destinationDeadline = Date(timeIntervalSinceNow: 3)
    while NSWorkspace.shared.frontmostApplication?.processIdentifier != destinationApp.processIdentifier && Date() < destinationDeadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destinationApp.processIdentifier else {
        fatalError("Could not focus destination; no mouse events sent")
    }
}
app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
let deadline = Date(timeIntervalSinceNow: 3)
while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier && Date() < deadline {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
    fatalError("Could not focus the isolated test app; no mouse events sent")
}
// Allow the window server to finish the foreground transition before posting.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
func contains(_ point: CGPoint, app: NSRunningApplication) -> Bool { windows.contains { window in
    guard window[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
          let dictionary = window[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
    if app.processIdentifier != testApp.processIdentifier {
        guard (window[kCGWindowName as String] as? String)?.contains("OpenCommander-MacUITest-") == true else { return false }
    }
    if windowMove { return bounds.contains(point) && point.y < bounds.minY + 32 }
    return bounds.contains(point)
} }
guard contains(CGPoint(x: sx, y: sy), app: app),
      windowMove ? CGDisplayBounds(CGMainDisplayID()).contains(CGPoint(x: dx, y: dy)) : contains(CGPoint(x: dx, y: dy), app: destinationApp) else {
    fatalError("Endpoints must be inside the isolated app or named Finder fixture window")
}
// A containing window may still be covered by another app. Never send the
// test gesture to an unrelated foreground window.
func visibleOwner(at point: CGPoint) -> Int32? {
    for window in windows {
        guard (window[kCGWindowLayer as String] as? Int) == 0,
              let dictionary = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
              bounds.contains(point) else { continue }
        // A permitted app can have unrelated windows above the fixture.
        // Browser and document tests must match the visible window as well.
        if let pid = window[kCGWindowOwnerPID as String] as? Int32,
           pid != testApp.processIdentifier,
           !(window[kCGWindowName as String] as? String ?? "").contains("OpenCommander-MacUITest-") { return nil }
        return window[kCGWindowOwnerPID as String] as? Int32
    }
    return nil
}
guard visibleOwner(at: CGPoint(x: sx, y: sy)) == app.processIdentifier,
      (windowMove || visibleOwner(at: CGPoint(x: dx, y: dy)) == destinationApp.processIdentifier) else {
    // Report only application identity and whether its title is allowlisted;
    // never print another document's title or content to diagnose coverage.
    func coverage(_ point: CGPoint) -> String {
        for window in windows {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary), bounds.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? Int32 else { continue }
            let name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
            let fixture = (window[kCGWindowName as String] as? String ?? "").contains("OpenCommander-MacUITest-")
            return "\(name), fixture=\(fixture), bounds=\(bounds)"
        }
        return "none"
    }
    let sourceOwner = coverage(CGPoint(x: sx, y: sy))
    let targetOwner = coverage(CGPoint(x: dx, y: dy))
    fputs("Covered endpoint owners: source=\(sourceOwner), target=\(targetOwner)\n", stderr)
    fatalError("A test endpoint is covered by another window; no mouse events sent")
}
let source = CGEventSource(stateID: .hidSystemState)
if ["--scroll-right", "--scroll-left"].contains(option) {
    guard installedFixture == nil, modifiers.isEmpty, behaviours.isEmpty, sx == dx, sy == dy,
          let bundleURL = testApp.bundleURL, let bundle = Bundle(url: bundleURL),
          let resource = bundle.url(forResource: "MacUITestRoot", withExtension: "txt"),
          let root = try? String(contentsOf: resource, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
          root.hasPrefix("/private/tmp/OpenCommander-MacUITest-"),
          FileManager.default.fileExists(atPath: root + "/Left"),
          FileManager.default.fileExists(atPath: root + "/Right") else {
        fatalError("Wheel test is restricted to a visible isolated fixture; no events sent")
    }
    let point = CGPoint(x: sx, y: sy)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    for _ in 0..<15 {
        let wheel = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                            wheel1: 0, wheel2: option == "--scroll-right" ? -40 : 40, wheel3: 0)
        wheel?.location = point; wheel?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.02)
    }
    print("POSTED guarded horizontal wheel; no mouse button, key or file mutation")
    exit(0)
}
var dragFlags: CGEventFlags = []
let modifierKeys: [CGKeyCode] = modifiers.map { $0 == "--option" ? 58 : 55 }
defer {
    for key in modifierKeys.reversed() {
        let release = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        release?.flags = []; release?.post(tap: .cghidEventTap)
    }
}
var previousPoint = CGPoint(x: sx, y: sy)
func event(_ type: CGEventType, x: Double, y: Double) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    event.flags = dragFlags
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.setIntegerValueField(.mouseEventNumber, value: 1)
    event.setDoubleValueField(.mouseEventPressure, value: type == .leftMouseUp ? 0 : 1)
    event.setIntegerValueField(.mouseEventDeltaX, value: Int64((x - previousPoint.x).rounded()))
    event.setIntegerValueField(.mouseEventDeltaY, value: Int64((y - previousPoint.y).rounded()))
    previousPoint = CGPoint(x: x, y: y)
    event.post(tap: .cghidEventTap)
}
event(.mouseMoved, x: sx, y: sy)
Thread.sleep(forTimeInterval: 0.15)
event(.leftMouseDown, x: sx, y: sy)
Thread.sleep(forTimeInterval: 0.8)
// Apply modifiers after selection so Command does not toggle the source row.
for key in modifierKeys {
    dragFlags.insert(key == 58 ? .maskAlternate : .maskCommand)
    let press = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    press?.flags = dragFlags; press?.post(tap: .cghidEventTap)
}
// Give Catalyst time to lift the item before crossing an application boundary.
let steps = !option.isEmpty ? 100 : 40
for step in 1...steps {
    let fraction = Double(step) / Double(steps)
    event(.leftMouseDragged, x: sx + (dx-sx)*fraction, y: sy + (dy-sy)*fraction)
    Thread.sleep(forTimeInterval: 0.025)
}
Thread.sleep(forTimeInterval: behaviours.contains("--hover") ? 5 : 0.3)
if cancel {
    // Cancel with plain Escape, not Command-Escape inherited from the
    // preceding modifier test. Keep the mouse held until cancellation settles.
    dragFlags = []
    for key in modifierKeys.reversed() {
        let release = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        release?.flags = []; release?.post(tap: .cghidEventTap)
    }
    Thread.sleep(forTimeInterval: 0.1)
    let escapeDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
    escapeDown?.flags = []; escapeDown?.post(tap: .cghidEventTap)
    let escapeUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
    escapeUp?.flags = []; escapeUp?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.15)
}
event(.leftMouseUp, x: dx, y: dy)
