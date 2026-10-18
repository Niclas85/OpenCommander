import Foundation

/// Display-only requests can share I/O. Cancellation belongs to each waiter;
/// cancelling one pane never cancels another pane's pending directory read.
@MainActor final class SharedDirectoryReads<Value> {
    private final class Entry {
        var waiters: [UUID: CheckedContinuation<Value, Error>] = [:]
        var task: Task<Void, Never>?
    }
    private var entries: [String: Entry] = [:]

    func value(for key: String, load: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let waiter = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if let entry = entries[key] { entry.waiters[waiter] = continuation; return }
                let entry = Entry(); entry.waiters[waiter] = continuation; entries[key] = entry
                entry.task = Task { [weak self, weak entry] in
                    let result: Result<Value, Error>
                    do { result = .success(try await load()) } catch { result = .failure(error) }
                    guard let self, let entry, self.entries[key] === entry else { return }
                    self.entries.removeValue(forKey: key)
                    let waiters = entry.waiters; entry.waiters.removeAll()
                    for continuation in waiters.values { continuation.resume(with: result) }
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancel(waiter, key: key) }
        })
    }
    private func cancel(_ waiter: UUID, key: String) {
        guard let entry = entries[key], let continuation = entry.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if entry.waiters.isEmpty { entries.removeValue(forKey: key); entry.task?.cancel() }
    }
    func invalidate() {
        let previous = entries; entries.removeAll()
        for entry in previous.values {
            entry.task?.cancel()
            let waiters = entry.waiters; entry.waiters.removeAll()
            for continuation in waiters.values { continuation.resume(throwing: CancellationError()) }
        }
    }
}
