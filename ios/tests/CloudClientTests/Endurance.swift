import Foundation
import CryptoKit
import Darwin

// Long-lived production clients and durable journals, not a loop that restarts
// the test process. All network failures are confined to injected adapters.
@MainActor private final class EnduranceBackend {
    let root: URL
    var offline = false
    var operations = 0
    var cancelled = 0
    private var pending: [String: Task<Void, Never>] = [:]
    init(_ root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func cancel(_ id: String) { pending[id]?.cancel() }
    var activeRequests: Int { pending.count }
    func perform(_ id: String, operation: String, path: String, destination: String?, local: URL?,
                 completion: @escaping (Data?, NSError?) -> Void) {
        pending[id] = Task { @MainActor in
            defer { pending.removeValue(forKey: id) }
            do {
                try await Task.sleep(nanoseconds: 15_000_000)
                try Task.checkCancellation()
                operations += 1
                if offline { throw URLError(.networkConnectionLost) }
                let fm = FileManager.default
                func scoped(_ path: String) throws -> URL {
                    guard CloudConnection.validRelative(path) else { throw CloudConnection.failure("cloud_invalid") }
                    let url = path.isEmpty ? root : root.appendingPathComponent(path)
                    guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw CloudConnection.failure("cloud_invalid") }
                    return url
                }
                let source = try scoped(path)
                var response = Data()
                switch operation {
                case "list":
                    let rows = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).map { url -> [String: Any] in
                        let attrs = try fm.attributesOfItem(atPath: url.path)
                        let directory = attrs[.type] as? FileAttributeType == .typeDirectory
                        let bytes = directory ? Data() : try Data(contentsOf: url)
                        return ["Name": url.lastPathComponent, "Path": url.lastPathComponent, "Size": directory ? 0 : bytes.count,
                            "IsDir": directory, "ID": String(describing: attrs[.systemFileNumber]!),
                            "ModTime": "2026-10-18T07:00:00Z", "Hashes": ["sha256": Data(SHA256.hash(data: bytes)).base64EncodedString()]]
                    }
                    response = try JSONSerialization.data(withJSONObject: rows)
                case "mkdir": try fm.createDirectory(at: source, withIntermediateDirectories: false)
                case "download": try fm.copyItem(at: source, to: local!)
                case "upload": try fm.copyItem(at: local!, to: source)
                case "copy": try fm.copyItem(at: source, to: scoped(destination!))
                case "rename": try fm.moveItem(at: source, to: scoped(destination!))
                case "deletefile": try fm.removeItem(at: source)
                case "rmdir":
                    guard try fm.contentsOfDirectory(atPath: source.path).isEmpty else { throw CocoaError(.fileWriteUnknown) }
                    try fm.removeItem(at: source)
                default: throw CloudConnection.failure("cloud_invalid")
                }
                completion(response, nil)
            } catch {
                if error is CancellationError { cancelled += 1; completion(nil, URLError(.cancelled) as NSError) }
                else { completion(nil, error as NSError) }
            }
        }
    }
}

@MainActor private final class EnduranceLane {
    let number: Int
    let root: URL
    let origin: EnduranceBackend
    let target: EnduranceBackend
    let sourceClient: CloudFileClient
    let targetClient: CloudFileClient
    var cycles = 0
    var outages = 0
    var pauses = 0
    var verifiedBytes: Int64 = 0
    var lastActivity = ProcessInfo.processInfo.systemUptime
    var phase = "created"
    private let source: URL
    private let journal: URL
    init(_ number: Int, root: URL) throws {
        self.number = number; self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        origin = try EnduranceBackend(root.appendingPathComponent("origin"))
        target = try EnduranceBackend(root.appendingPathComponent("target"))
        source = origin.root.appendingPathComponent("Payload.bin")
        journal = root.appendingPathComponent("journal")
        func client(_ backend: EnduranceBackend, _ suffix: String) -> CloudFileClient {
            let profile = CloudConnection(name: "Endurance \(number) \(suffix)", kind: "drive", remote: "synthetic",
                configPath: root.appendingPathComponent("unused-private.conf").path)
            return CloudFileClient(profile, transport: { id, _, operation, path, destination, local, done in
                backend.perform(id, operation: operation, path: path, destination: destination, local: local, completion: done)
            }, cancel: { id in Task { @MainActor in backend.cancel(id) } })
        }
        sourceClient = client(origin, "source"); targetClient = client(target, "target")
    }
    private func step(_ name: String) { phase = name; lastActivity = ProcessInfo.processInfo.systemUptime }
    private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "OpenCommander.Endurance", code: number, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    func run(until deadline: TimeInterval) async throws {
        let fm = FileManager.default
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            step("prepare")
            let bytes = Data(repeating: UInt8((cycles + number) % 251), count: 128 * 1024)
            try bytes.write(to: source, options: .atomic)
            let item = try await sourceClient.children(of: nil).first { $0.name == "Payload.bin" }!
            let job = try await PendingCrossCloudMove.prepare(item, source: sourceClient, target: targetClient,
                parent: nil, name: "Result.bin", sourceLocation: "synthetic-source:/Payload.bin",
                destinationLocation: "synthetic-target:/Result.bin", root: journal)
            // Network loss is local to this lane. No host interfaces, accounts
            // or real provider configuration are touched.
            step("network-loss"); target.offline = true
            do {
                _ = try await PendingCrossCloudMove.resume(job, source: sourceClient, target: targetClient, root: journal)
                throw NSError(domain: "OpenCommander.Endurance.UnexpectedSuccess", code: 1)
            } catch {
                if (error as NSError).domain == "OpenCommander.Endurance.UnexpectedSuccess" { throw error }
                outages += 1
            }
            target.offline = false
            try check(try Data(contentsOf: source) == bytes, "outage changed the original source")
            if cycles % 3 == 0 {
                step("pause-request")
                let transfer = Task { @MainActor in
                    try await PendingCrossCloudMove.resume(job, source: sourceClient, target: targetClient, root: journal)
                }
                try await Task.sleep(nanoseconds: 25_000_000)
                transfer.cancel()
                do {
                    _ = try await transfer.value
                    throw NSError(domain: "OpenCommander.Endurance.UnexpectedSuccess", code: 2)
                } catch {
                    if (error as NSError).domain == "OpenCommander.Endurance.UnexpectedSuccess" { throw error }
                    pauses += 1
                }
                try check(try Data(contentsOf: source) == bytes, "pause changed the source")
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            step("resume")
            let restored = try PendingCrossCloudMove.pending(root: journal).first!
            let undo = try await PendingCrossCloudMove.resume(restored, source: sourceClient, target: targetClient, root: journal)
            try check(try Data(contentsOf: target.root.appendingPathComponent("Result.bin")) == bytes, "published bytes differ")
            try check(!fm.fileExists(atPath: source.path), "move left original visible")
            step("undo")
            let persisted = try JSONDecoder().decode(CloudUndoPayload.self, from: JSONEncoder().encode(undo))
            _ = try await PersistentOnlineUndo.undo(persisted, client: targetClient, sourceClient: sourceClient)
            try check(try Data(contentsOf: source) == bytes, "Undo source bytes differ")
            try check(!fm.fileExists(atPath: target.root.appendingPathComponent("Result.bin").path), "Undo left visible target")
            try PendingCrossCloudMove.finish(restored, root: journal)
            try check(try PendingCrossCloudMove.pending(root: journal).isEmpty, "finished journal remains pending")
            // Reclamation is only of this disposable lane's private recovery
            // copies, after independently checking the restored original.
            for backend in [origin, target] {
                for child in try fm.contentsOfDirectory(at: backend.root, includingPropertiesForKeys: nil)
                    where child.lastPathComponent.hasPrefix(".OpenCommander-") { try fm.removeItem(at: child) }
            }
            cycles += 1; verifiedBytes += Int64(bytes.count) * 2
            step("verified")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        step("completed")
    }
    var metrics: [String: Any] {
        ["lane": number, "cycles": cycles, "outages": outages, "pauses": pauses, "verifiedBytes": verifiedBytes,
         "phase": phase, "lastActivityUptime": lastActivity, "operations": origin.operations + target.operations,
         "activeRequests": origin.activeRequests + target.activeRequests, "cancelledRequests": origin.cancelled + target.cancelled]
    }
}

@main struct CloudEnduranceTests {
    @MainActor static func main() async {
        let fm = FileManager.default
        guard CommandLine.arguments.count == 3, let seconds = Double(CommandLine.arguments[2]), seconds >= 10, seconds <= 24 * 3600,
              let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("Expected isolated root and duration (10..86400 seconds)") }
        defer { free(physical) }
        let root = URL(fileURLWithPath: String(cString: physical))
        guard root.path.hasPrefix("/private/tmp/OpenCommander-Endurance-"), root.deletingLastPathComponent().path == "/private/tmp",
              (try? fm.contentsOfDirectory(atPath: root.path).isEmpty) == true else { fatalError("Root must be a new empty endurance fixture") }
        let start = ProcessInfo.processInfo.systemUptime, started = Date()
        var lanes = [EnduranceLane]()
        var status = "running"
        func report(_ failure: String? = nil) throws {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            let descriptors = (0..<256).filter { fcntl(Int32($0), F_GETFD) != -1 }.count
            let freeBytes = (try? fm.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? -1
            let data: [String: Any] = ["status": status, "startedAt": ISO8601DateFormatter().string(from: started),
                "updatedAt": ISO8601DateFormatter().string(from: Date()), "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
                "requiredSeconds": seconds, "lanes": lanes.map(\.metrics), "maxRSSBytes": usage.ru_maxrss,
                "openDescriptorsBelow256": descriptors, "hostFreeBytes": freeBytes, "failure": failure ?? ""]
            try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
                .write(to: root.appendingPathComponent("status.json"), options: .atomic)
        }
        do {
            for n in 1...4 { lanes.append(try EnduranceLane(n, root: root.appendingPathComponent("lane-\(n)"))) }
            try report()
            print("START four long-lived cloud lanes, duration=\(seconds), isolated adapter network failures; \(root.path)")
            fflush(stdout)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for lane in lanes { group.addTask { try await lane.run(until: start + seconds) } }
                group.addTask { @MainActor in
                    while ProcessInfo.processInfo.systemUptime < start + seconds {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        for lane in lanes where lane.phase != "completed" && ProcessInfo.processInfo.systemUptime - lane.lastActivity > 120 {
                            throw NSError(domain: "OpenCommander.Endurance.Stalled", code: lane.number)
                        }
                        try report()
                    }
                }
                try await group.waitForAll()
            }
            guard lanes.allSatisfy({ $0.cycles > 0 && $0.outages > 0 && $0.pauses > 0 && $0.phase == "completed" }),
                  ProcessInfo.processInfo.systemUptime - start >= seconds else { throw NSError(domain: "OpenCommander.Endurance.Incomplete", code: 1) }
            status = "passed"; try report()
            print("PASS \(seconds)-second continuous production-cloud-client endurance: four independent lanes, outage/pause/resume, exact bytes and persistent Undo")
        } catch {
            status = "failed"; try? report(String(describing: error))
            fputs("FAIL endurance: \(error)\n", stderr); exit(1)
        }
    }
}
