import Foundation

enum OneDriveUploadOutageTest {
    private final class Provider {
        enum Phase { case loseFirstReply, rejectStatus(Int), failSecondReply, finish }
        private let lock = NSLock()
        private let data: Data
        private var phase: Phase = .loseFirstReply
        private var accepted = Data()
        private var offsets: [Int] = []
        private var sessions = 0
        private var statusReads = 0

        init(_ data: Data) { self.data = data }

        func enter(_ phase: Phase) {
            lock.withLock { self.phase = phase }
        }

        func verify(sessions expectedSessions: Int, reads: Int, offsets expectedOffsets: [Int], completed: Bool = false) {
            lock.withLock {
                precondition(sessions == expectedSessions && statusReads == reads && offsets == expectedOffsets)
                if completed { precondition(accepted == data) }
            }
        }

        func respond(to request: URLRequest) throws -> (Int, String) {
            try lock.withLock {
                let url = request.url!
                let method = request.httpMethod!
                if url.host == "login.microsoftonline.com" {
                    return (200, #"{"access_token":"only-in-test","expires_in":3600}"#)
                }
                if url.host == "graph.microsoft.com" {
                    precondition(method == "POST" && url.path.hasSuffix("/createUploadSession"))
                    sessions += 1
                    return (200, #"{"uploadUrl":"https://example.invalid/session"}"#)
                }
                precondition(url == URL(string: "https://example.invalid/session"))
                precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
                if method == "GET" {
                    statusReads += 1
                    if case .rejectStatus(let status) = phase { return (status, "<html>Test gateway unavailable</html>") }
                    return (200, remaining)
                }
                precondition(method == "PUT")
                let offset = accepted.count
                let fragment = OneDriveTests.body(request)
                let end = offset + fragment.count
                precondition(fragment.count > 0 && end <= data.count)
                precondition(request.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(end-1)/\(data.count)")
                precondition(fragment == data.subdata(in: offset..<end))
                offsets.append(offset)
                accepted.append(fragment)
                if case .loseFirstReply = phase { throw URLError(.networkConnectionLost) }
                if case .failSecondReply = phase { return (500, "<html>Test gateway unavailable</html>") }
                if end == data.count { return (201, #"{"id":"own","name":"Payload.bin","size":\#(end),"file":{}}"#) }
                return (202, remaining)
            }
        }

        private var remaining: String { #"{"nextExpectedRanges":["\#(accepted.count)-"]}"# }
    }

    @MainActor static func run() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommander-UploadOutage-" + UUID().uuidString)
        let checkpoints = fixture.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("Payload.bin")
        let block = 3_276_800
        let payload = [1, 2, 3, 4].reduce(into: Data()) { $0.append(Data(repeating: $1, count: block)) }
        try payload.write(to: source, options: .withoutOverwriting)
        let provider = Provider(payload)
        MockMicrosoft.handler = provider.respond
        MockMicrosoft.headers = [:]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockMicrosoft.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); MockMicrosoft.headers = [:] }
        let clientID = UUID().uuidString
        func newClient() -> OneDriveClient {
            let client = OneDriveClient(clientID: clientID, session: session, store: MemoryTokens())
            client.uploadSessionDirectory = checkpoints
            client.uploadRecoveryAccount = "own-test-drive"
            return client
        }
        do {
            try await newClient().upload(source, parent: "test-folder")
            fatalError("The test transport lost the first upload reply")
        } catch let error as URLError where error.code == .networkConnectionLost {}
        let markers = try FileManager.default.contentsOfDirectory(at: checkpoints, includingPropertiesForKeys: nil)
        precondition(markers.count == 1)
        let marker = markers[0]
        let saved = try Data(contentsOf: marker)
        provider.verify(sessions: 1, reads: 0, offsets: [0])

        MockMicrosoft.headers = ["Retry-After": "47"]
        for (index, status) in [503, 429].enumerated() {
            provider.enter(.rejectStatus(status))
            do {
                try await newClient().upload(source, parent: "test-folder")
                fatalError("An unavailable session was treated as a verified offset")
            } catch OneDriveFailure.temporarilyUnavailable(let observed, let delay) {
                precondition(observed == status && delay == 47)
            }
            provider.verify(sessions: 1, reads: index + 1, offsets: [0])
            let intact = try Data(contentsOf: marker)
            precondition(intact == saved)
        }
        print("PASS Graph upload resumes never write after HTML HTTP 503 or 429; checkpoint and provider wait survive")

        provider.enter(.failSecondReply)
        do {
            try await newClient().upload(source, parent: "test-folder")
            fatalError("A fragment error was treated as success")
        } catch OneDriveFailure.temporarilyUnavailable(let observed, let delay) {
            precondition(observed == 500 && delay == 47)
        }
        provider.verify(sessions: 1, reads: 3, offsets: [0, block])
        let intact = try Data(contentsOf: marker)
        precondition(intact == saved)

        provider.enter(.finish)
        try await newClient().upload(source, parent: "test-folder")
        provider.verify(sessions: 1, reads: 4, offsets: [0, block, 2 * block, 3 * block], completed: true)
        let onDisk = try Data(contentsOf: source)
        precondition(onDisk == payload && !FileManager.default.fileExists(atPath: marker.path))
        print("PASS lost Graph fragment replies resume at the server offset with exact bytes and no replay")
    }
}
