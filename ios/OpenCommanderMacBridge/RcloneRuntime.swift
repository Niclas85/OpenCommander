#if os(macOS)
import Foundation
import CryptoKit
import Darwin

/// Bounded native child processes. No shell, inherited rclone credentials,
/// stderr logging, or user-controlled executable path.
final class RcloneProcessRunner {
    private let lock = NSLock()
    private var processes: [String: Process] = [:]
    private var cancelled = Set<String>()
    func cancel(_ id: String) {
        lock.lock(); cancelled.insert(id); let process = processes[id]; lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }
    func check(_ id: String) throws {
        lock.lock(); let stopped = cancelled.contains(id); lock.unlock()
        if stopped { throw CancellationError() }
    }
    func finish(_ id: String) { lock.lock(); cancelled.remove(id); lock.unlock() }
    func run(_ executable: URL, _ arguments: [String], id: String, timeout: TimeInterval = 60,
             maximumOutput: Int = 32 * 1024 * 1024, input: Data? = nil, environment: [String: String] = [:],
             browser: ((URL) -> Void)? = nil, setupKind: String? = nil) throws -> Data {
        guard (input?.count ?? 0) <= 16384, environment.allSatisfy({ key, value in
            key.hasPrefix("RCLONE_") && key.range(of: #"^[A-Z0-9_]+$"#, options: .regularExpression) != nil && value.utf8.count <= 16384 && !value.contains("\0")
        }) else { throw CloudConnection.failure("cloud_invalid") }
        let process = Process(), pipe = Pipe(), errorPipe = Pipe()
        let inputPipe = input == nil ? nil : Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = errorPipe
        if let inputPipe { process.standardInput = inputPipe } else { process.standardInput = FileHandle.nullDevice }
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        process.environment?.merge(environment) { _, new in new }
        lock.lock()
        if cancelled.contains(id) { lock.unlock(); throw CancellationError() }
        processes[id] = process
        do { try process.run() } catch { processes.removeValue(forKey: id); lock.unlock(); throw error }
        lock.unlock()
        let errorOutput = RuntimeErrorOutput()
        let errorFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            defer { errorFinished.signal() }
            var browserSent = false
            while let chunk = try? errorPipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                errorOutput.append(chunk)
                if !browserSent, let browser, let url = CloudSetupQuestion.browserURL(errorOutput.data) {
                    browserSent = true; browser(url)
                }
            }
        }
        if let input, let inputPipe {
            do { try inputPipe.fileHandleForWriting.write(contentsOf: input); try inputPipe.fileHandleForWriting.close() }
            catch { if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit(); throw CloudConnection.failure("cloud_request_failed") }
        }
        defer { lock.lock(); processes.removeValue(forKey: id); lock.unlock() }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let deadline = Date().addingTimeInterval(timeout)
        let timeoutState = RuntimeFlag()
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard process.isRunning else { return }
            let expired = Date() >= deadline
            if expired || (try? self?.check(id)) == nil {
                if expired { timeoutState.set() }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        timer.resume(); defer { timer.cancel() }
        var output = Data()
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                guard chunk.count <= maximumOutput - output.count else { throw CloudConnection.failure("cloud_limit") }
                output.append(chunk)
            }
        } catch {
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit(); throw error
        }
        process.waitUntilExit(); try check(id)
        _ = errorFinished.wait(timeout: .now() + 1)
        guard !timeoutState.value else { throw CloudProviderErrors.temporary("cloud_timeout") }
        guard process.terminationStatus == 0 else {
            if let setupKind { throw CloudSetupQuestion.loginFailure(kind: setupKind, detail: String(decoding: errorOutput.data, as: UTF8.self)) }
            throw CloudProviderErrors.classify(errorOutput.data)
        }
        return output
    }
}

private final class RuntimeErrorOutput {
    private let lock = NSLock()
    private var storage = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        storage.append(data.prefix(max(0, 16 * 1024 - storage.count)))
    }
}

private final class RuntimeFlag {
    private let lock = NSLock(); private var state = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return state }
    func set() { lock.lock(); state = true; lock.unlock() }
}

/// Downloads only from the official HTTPS host, enforces a disk/response limit,
/// validates the ZIP SHA-256, then atomically installs an app-private executable.
final class RcloneRuntime {
    private static let installation = NSLock()
    let root: URL
    let runner: RcloneProcessRunner
    var status: ((String) -> Void)?
    init(root: URL? = nil, runner: RcloneProcessRunner) {
        self.runner = runner
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenCommander/Runtime", isDirectory: true)
    }
    private func privateDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
            url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        guard chmod(url.path, 0o700) == 0 else { throw CloudConnection.failure("cloud_runtime_unsafe") }
    }
    static func hash(_ file: URL, limit: Int64 = 128 * 1024 * 1024) throws -> String {
        var info = stat()
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_size <= limit else { throw CloudConnection.failure("cloud_limit") }
        var hash = SHA256(), count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            count += Int64(chunk.count); guard count <= limit else { throw CloudConnection.failure("cloud_limit") }
            hash.update(data: chunk)
        }
        guard count == info.st_size else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func executable(id: String) throws -> URL {
        while !Self.installation.try() { try runner.check(id); Thread.sleep(forTimeInterval: 0.05) }
        defer { Self.installation.unlock() }
        try runner.check(id); try privateDirectory(root)
        let binary = root.appendingPathComponent("rclone"), marker = root.appendingPathComponent("binary-sha256.txt")
        if FileManager.default.isExecutableFile(atPath: binary.path) {
            guard let expected = try? String(contentsOf: marker, encoding: .utf8), expected.count == 64,
                try Self.hash(binary) == expected else { throw CloudConnection.failure("cloud_runtime_unsafe") }
            return binary
        }
        let temp = root.appendingPathComponent("download-" + UUID().uuidString, isDirectory: true)
        try privateDirectory(temp); defer { try? FileManager.default.removeItem(at: temp) }
        status?("cloud_runtime_metadata")
        let versionData = try fetch(URL(string: "https://downloads.rclone.org/version.txt")!, to: temp.appendingPathComponent("version"), id: id, limit: 2 * 1024 * 1024)
        let version = String(decoding: versionData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.range(of: #"^rclone v[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        let release = String(version.dropFirst(7))
        let numbers = release.dropFirst().split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3, !numbers.lexicographicallyPrecedes([1, 75, 2]) else { throw CloudConnection.failure("cloud_runtime_unsafe") }
#if arch(arm64)
        let architecture = "arm64"
#else
        let architecture = "amd64"
#endif
        let name = "rclone-\(release)-osx-\(architecture)", base = "https://downloads.rclone.org/\(release)/"
        let checksum = try fetch(URL(string: base + "SHA256SUMS")!, to: temp.appendingPathComponent("checksums"), id: id, limit: 2 * 1024 * 1024)
        let expected = String(decoding: checksum, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name + ".zip" else { return nil }
            return String(parts[0])
        }
        guard expected.count == 1, expected[0].range(of: #"^[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        let archive = temp.appendingPathComponent("runtime.zip")
        status?("cloud_runtime_download")
        _ = try fetch(URL(string: base + name + ".zip")!, to: archive, id: id, limit: 128 * 1024 * 1024, read: false)
        status?("cloud_runtime_verify")
        guard try Self.hash(archive) == expected[0].lowercased() else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        status?("cloud_runtime_extract")
        let extracted = try runner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", archive.path, name + "/rclone"], id: id, timeout: 30, maximumOutput: 128 * 1024 * 1024)
        let candidate = temp.appendingPathComponent("rclone")
        try extracted.write(to: candidate, options: .withoutOverwriting); guard chmod(candidate.path, 0o700) == 0 else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        let found = try runner.run(candidate, ["version"], id: id, timeout: 10, maximumOutput: 64 * 1024)
        guard String(decoding: found, as: UTF8.self).hasPrefix(version + "\n") else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        let license = try runner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", archive.path, name + "/README.txt"], id: id, timeout: 10, maximumOutput: 8 * 1024 * 1024)
        try runner.check(id)
        try license.write(to: root.appendingPathComponent("rclone-README.txt"), options: .atomic)
        let digest = try Self.hash(candidate)
        try Data(digest.utf8).write(to: marker, options: .atomic)
        guard rename(candidate.path, binary.path) == 0 else { throw CloudConnection.failure("cloud_runtime_unsafe") }
        return binary
    }
    private func fetch(_ url: URL, to destination: URL, id: String, limit: Int64, read: Bool = true) throws -> Data {
        let fetch = RuntimeDownload(destination: destination, limit: limit)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: fetch, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: url); task.resume()
        let deadline = Date().addingTimeInterval(305)
        while fetch.done.wait(timeout: .now() + 0.1) != .success {
            do { try runner.check(id); guard Date() < deadline else { throw CloudConnection.failure("cloud_timeout") } }
            catch { task.cancel(); throw error }
        }
        if let error = fetch.error { throw error }
        guard FileManager.default.fileExists(atPath: destination.path) else { throw CloudConnection.failure("cloud_request_failed") }
        return read ? try Data(contentsOf: destination) : Data()
    }
}

private final class RuntimeDownload: NSObject, URLSessionDownloadDelegate {
    let destination: URL; let limit: Int64; let done = DispatchSemaphore(value: 0)
    var error: Error?
    init(destination: URL, limit: Int64) { self.destination = destination; self.limit = limit }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "downloads.rclone.org" ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { error = CloudConnection.failure("cloud_limit"); downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                response.url?.scheme == "https", response.url?.host == "downloads.rclone.org",
                let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, Int64(size) <= limit else { throw CloudConnection.failure("cloud_runtime_unsafe") }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { self.error = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if self.error == nil { self.error = error }; done.signal()
    }
}
#endif
