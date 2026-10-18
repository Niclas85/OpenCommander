import Foundation
import CryptoKit
import Darwin

/// References an explicitly chosen rclone remote; credentials stay in its
/// private config and never enter location preferences or history.
struct CloudConnection: Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var kind: String
    var remote: String
    var root: String = ""
    var configPath: String
    var locationPath: String { "cloud://" + id }
    static let defaultsKey = "cloud_connections_v1"
    static let kinds = ["drive", "onedrive", "dropbox", "iclouddrive"]
    static func load() -> [CloudConnection] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        guard data.count <= 1024 * 1024, let values = try? JSONDecoder().decode([Self].self, from: data),
            values.count <= 100, Set(values.map(\.id)).count == values.count else { return [] }
        return values.filter { (try? $0.validate()) != nil }
    }
    static func save(_ values: [CloudConnection]) throws {
        guard values.count <= 100, Set(values.map(\.id)).count == values.count else { throw failure("cloud_invalid") }
        for value in values { try value.validate() }
        UserDefaults.standard.set(try JSONEncoder().encode(values), forKey: defaultsKey)
    }
    static func validRelative(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\0") &&
        (path.isEmpty || path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." })
    }
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
    func validate() throws {
        guard UUID(uuidString: id) != nil, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 512, Self.kinds.contains(kind), !remote.isEmpty, remote.utf8.count <= 255, !remote.hasPrefix("-"),
              !remote.contains(where: { $0 == ":" || $0 == "/" || $0 == "\\" || $0 == "\0" || $0.isNewline }),
              Self.validRelative(root), root.utf8.count <= 4096, configPath.hasPrefix("/"), configPath.utf8.count <= 4096, !configPath.contains("\0"),
              !configPath.split(separator: "/").contains("..") else { throw Self.failure("cloud_invalid") }
    }
    func address(_ relative: String) throws -> String {
        try validate(); guard Self.validRelative(relative) else { throw Self.failure("cloud_invalid") }
        return remote + ":" + [root, relative].filter { !$0.isEmpty }.joined(separator: "/")
    }
    var website: URL? {
        let sites = ["drive": "https://drive.google.com/drive/my-drive", "onedrive": "https://onedrive.live.com/",
                     "dropbox": "https://www.dropbox.com/home", "iclouddrive": "https://www.icloud.com/iclouddrive/"]
        return sites[kind].flatMap(URL.init(string:))
    }
    static func failure(_ key: String) -> NSError {
        NSError(domain: "OpenCommander.Cloud", code: 1, userInfo: [NSLocalizedDescriptionKey: key])
    }
}

/// CLI arguments are structured and bounded. No user command strings, mounts,
/// deletes of directory trees, automatic retries or plaintext credential arguments.
enum RcloneCommandPlan {
    static func arguments(profile: CloudConnection, operation: String, path: String,
                          destination: String? = nil, local: URL? = nil) throws -> [String] {
        try profile.validate()
        guard CloudConnection.validRelative(path), path.utf8.count <= 4096,
              destination.map({ CloudConnection.validRelative($0) && $0.utf8.count <= 4096 }) != false else { throw CloudConnection.failure("cloud_invalid") }
        let global = ["--config", profile.configPath, "--ask-password=false", "--retries", "1", "--low-level-retries", "1",
            "--contimeout", "15s", "--timeout", "30s", "--log-level", "ERROR"]
        let address = try profile.address(path)
        func localPath() throws -> String {
            guard let local, local.isFileURL, local.path.hasPrefix("/"), !local.path.contains("\0"),
                local.path.utf8.count <= 4096 else { throw CloudConnection.failure("cloud_invalid") }
            return local.path
        }
        switch operation {
        case "profiles": return ["listremotes", "--json", "--source", "file"] + global
        case "list": return ["lsjson", "--hash"] + global + ["--", address]
        case "stat": return ["lsjson", "--stat", "--hash"] + global + ["--", address]
        case "mkdir", "rmdir", "deletefile":
            guard !path.isEmpty else { throw CloudConnection.failure("cloud_invalid") }
            return [operation] + global + ["--", address]
        case "download": return ["copyto", "--immutable"] + global + ["--", address, try localPath()]
        case "export":
            guard profile.kind == "drive", !path.isEmpty else { throw CloudConnection.failure("cloud_invalid") }
            return ["copyto", "--immutable", "--max-transfer", "256Mi", "--cutoff-mode", "HARD"] + global + ["--", address, try localPath()]
        case "upload":
            guard !path.isEmpty else { throw CloudConnection.failure("cloud_invalid") }
            return ["copyto", "--immutable"] + global + ["--", try localPath(), address]
        case "copy", "rename", "copytree", "renametree":
            guard !path.isEmpty, let destination, !destination.isEmpty, path != destination,
                !destination.hasPrefix(path + "/"), !path.hasPrefix(destination + "/") else { throw CloudConnection.failure("cloud_invalid") }
            let command = ["copy": "copyto", "rename": "moveto", "copytree": "copy", "renametree": "move"][operation]!
            let flags = operation == "copytree" ? ["--create-empty-src-dirs"] : operation == "renametree" ? ["--create-empty-src-dirs", "--delete-empty-src-dirs"] : []
            return [command, "--immutable"] + flags + global + ["--", address, try profile.address(destination)]
        default: throw CloudConnection.failure("cloud_invalid")
        }
    }
}

struct RcloneListingItem: Decodable {
    let Name: String
    let Path: String
    let Size: Int64
    let IsDir: Bool
    let ModTime: String?
    let ID: String?
    let Hashes: [String: String]?
    func validate(root: Bool = false) throws {
        guard (root && Name.isEmpty) || CloudConnection.validName(Name),
              CloudConnection.validRelative(Path), Size >= -1 else { throw CloudConnection.failure("cloud_invalid_listing") }
    }
}

struct RcloneRemoteInfo: Codable {
    let name: String
    let type: String
    let source: String
    let description: String?
}

struct CloudSetupQuestion: Codable {
    struct Field: Codable {
        struct Choice: Codable { let Value: String; let Help: String? }
        let Name: String
        let IsPassword: Bool?
        let Required: Bool?
        let DefaultStr: String?
        let Examples: [Choice]?
    }
    let State: String?
    let Option: Field?
    let Error: String?
    var complete: Bool { (State ?? "").isEmpty && (Error ?? "").isEmpty }
    func automaticAnswer(kind: String) -> String? {
        guard let option = Option else { return nil }
        switch option.Name {
        case "config_is_local", "config_refresh_token": return "true"
        case "config_change_team_drive" where kind == "drive": return "false"
        case "service" where kind == "iclouddrive": return "drive"
        case "config_advanced", "config_fs_advanced", "client_id", "client_secret", "region", "encoding",
             "root_folder_id", "team_drive", "chunk_size", "upload_cutoff", "list_chunk", "pacer_min_sleep", "pacer_burst", "use_trash":
            return option.DefaultStr ?? ""
        default: return nil
        }
    }
    static func decode(_ data: Data, kind: String) throws -> Self {
        guard data.count <= 256 * 1024 else { throw CloudConnection.failure("cloud_limit") }
        let question = try JSONDecoder().decode(Self.self, from: data)
        if let error = question.Error, !error.isEmpty { throw loginFailure(kind: kind, detail: error) }
        guard (question.State?.utf8.count ?? 0) <= 8192,
            question.State?.contains("\0") != true,
            question.complete || question.Option != nil else { throw CloudConnection.failure("cloud_login_incomplete") }
        if let option = question.Option {
            guard option.Name.range(of: #"^[A-Za-z0-9_]{1,100}$"#, options: .regularExpression) != nil,
                (option.DefaultStr?.utf8.count ?? 0) <= 16384, (option.Examples?.count ?? 0) <= 1000,
                option.Examples?.allSatisfy({ $0.Value.utf8.count <= 8192 && ($0.Help?.utf8.count ?? 0) <= 4096 }) != false else {
                throw CloudConnection.failure("cloud_limit")
            }
        }
        return question
    }
    static func browserURL(_ data: Data) -> URL? {
        let text = String(decoding: data.prefix(16384), as: UTF8.self)
        guard let range = text.range(of: #"http://127\.0\.0\.1:53682/auth\?state=[A-Za-z0-9_-]{22}(?=\s|$)"#, options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }
    static func loginFailure(kind: String, detail: String) -> NSError {
        let value = detail.prefix(16384).lowercased()
        if kind == "drive" {
            // Never display raw backend replies: they can contain credentials.
            // Authentication takes precedence over an incidental quota mention.
            if value.contains("invalid_grant") || value.contains("invalid credentials") || value.range(of: #"\b401\b"#, options: .regularExpression) != nil {
                return CloudConnection.failure("cloud_google_login_expired")
            }
            if value.contains("shared") && ["retired", "quota", "ratelimit", "rate limit"].contains(where: value.contains) {
                return CloudConnection.failure("cloud_google_shared_unavailable")
            }
            if ["quota", "ratelimit", "rate limit"].contains(where: value.contains) { return CloudConnection.failure("cloud_rate_limited") }
        }
        if kind == "iclouddrive" {
            if value.contains("missing pcs cookies") || value.contains("requestpcs:") { return CloudConnection.failure("cloud_icloud_web_access") }
            if value.range(of: #"\b401\b"#, options: .regularExpression) != nil || value.contains("invalid credentials") { return CloudConnection.failure("cloud_icloud_login_denied") }
            return CloudConnection.failure("cloud_icloud_verification")
        }
        return CloudConnection.failure("cloud_login_incomplete")
    }
}

/// Inspect only the explicitly chosen section. Never expose credential values
/// through errors, preferences, History or diagnostics.
enum CloudConfigurationValidator {
    static func identity(_ profile: CloudConnection) throws -> String {
        try profile.validate()
        let descriptor = open(profile.configPath, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CloudConnection.failure("cloud_config_private") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var initial = stat(), final = stat()
        guard fstat(descriptor, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG,
            initial.st_uid == geteuid(), initial.st_mode & 0o077 == 0,
            initial.st_size > 0, initial.st_size <= 1024 * 1024 else { throw CloudConnection.failure("cloud_config_private") }
        let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard data.count == initial.st_size, fstat(descriptor, &final) == 0,
            initial.st_dev == final.st_dev, initial.st_ino == final.st_ino,
            initial.st_size == final.st_size, initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
            initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec,
            initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec,
            initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec else { throw CloudConnection.failure("cloud_config_changed") }
        try validate(data, profile: profile)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func validate(_ data: Data, profile: CloudConnection) throws {
        try profile.validate()
        guard data.count <= 1024 * 1024, let text = String(data: data, encoding: .utf8),
              !text.hasPrefix("RCLONE_ENCRYPT_V") else { throw CloudConnection.failure("cloud_config_unreadable") }
        var current: String?, selected: [String: String] = [:], sections = Set<String>()
        for raw in text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, sections.insert(name).inserted, sections.count <= 1000 else {
                    throw CloudConnection.failure("cloud_config_unreadable")
                }
                current = name
            } else if current == profile.remote, let separator = line.firstIndex(of: "=") {
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, selected[key] == nil else { throw CloudConnection.failure("cloud_config_unreadable") }
                selected[key] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard selected["type"] == profile.kind else { throw CloudConnection.failure("cloud_config_changed") }
        func present(_ key: String) -> Bool { selected[key]?.isEmpty == false }
        if ["drive", "onedrive", "dropbox"].contains(profile.kind) {
            guard let encoded = selected["token"], let json = encoded.data(using: .utf8),
                  let token = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let access = token["access_token"] as? String, !access.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudConnection.failure("cloud_login_incomplete")
            }
            if profile.kind == "onedrive", !(present("drive_id") && present("drive_type")) {
                throw CloudConnection.failure("cloud_drive_incomplete")
            }
        } else if profile.kind == "iclouddrive" {
            guard present("apple_id"), let password = selected["password"], obscured(password) else {
                throw CloudConnection.failure("cloud_icloud_incomplete")
            }
            guard present("trust_token"), present("cookies") else { throw CloudConnection.failure("cloud_icloud_verification") }
        }
    }
    static func obscured(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 * 1024,
              value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-=").contains($0) }) else { return false }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)
        return (Data(base64Encoded: base64)?.count ?? 0) >= 16
    }
}

enum CloudProviderErrors {
    static func temporary(_ key: String, cooldown: TimeInterval = 10) -> NSError {
        NSError(domain: "OpenCommander.Cloud", code: 2,
            userInfo: [NSLocalizedDescriptionKey: key, "retryAfter": cooldown])
    }
    static func cooldown(_ error: Error) -> TimeInterval? {
        let value = error as NSError
        guard value.domain == "OpenCommander.Cloud", value.code == 2 else { return nil }
        return max(10, min(300, value.userInfo["retryAfter"] as? TimeInterval ?? 10))
    }
    static func classify(_ data: Data) -> NSError {
        let text = String(decoding: data.prefix(16 * 1024), as: UTF8.self).lowercased()
        if ["invalid_grant", "unauthorized", "401", "token expired", "invalid credentials", "invalid session", "couldn't decrypt password"].contains(where: text.contains) {
            return CloudConnection.failure("cloud_login_incomplete")
        }
        if text.contains("defaultperminuteperproject") { return temporary("cloud_google_quota", cooldown: 60) }
        if ["ratelimitexceeded", "rate_limit_exceeded", "userratelimitexceeded", "quota exceeded", "429", "too many requests"].contains(where: text.contains) {
            return temporary("cloud_rate_limited")
        }
        if ["timeout", "timed out", "temporary failure", "connection reset", "connection refused", "network is unreachable", "no such host", "server error", "503 service", "502 bad gateway", "504 gateway", "500 internal"].contains(where: text.contains) {
            return temporary("cloud_temporarily_unavailable")
        }
        // Credential-bearing provider output is never included in this error.
        return CloudConnection.failure("cloud_request_failed")
    }
}
