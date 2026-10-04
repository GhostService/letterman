import Foundation

/// Hour logs that couldn't reach the server (no signal at the volunteer site).
/// Saved on the phone, encrypted by iOS file protection, and uploaded on the next refresh,
/// so a supervisor's signature is never lost.
struct PendingLog: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Set when this is an edit or signature for a log that's already on the server.
    var remoteID: String?
    /// The id a new log is created with. Fixed up front so a retry after a lost response
    /// finds the log it already created instead of making a duplicate.
    var recordID = PendingLog.newRecordID()
    var draft: LogDraft
    /// Why the server refused it last time, if it did. Shown so the volunteer can fix or discard it.
    var problem: String?

    /// PocketBase ids are 15 characters of a-z and 0-9.
    static func newRecordID() -> String {
        String((0..<15).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    }
}

enum Outbox {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("outbox.json")
    }

    static func load() -> [PendingLog] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingLog].self, from: data)) ?? []
    }

    static func save(_ items: [PendingLog]) {
        if items.isEmpty { return clear() }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension Error {
    /// True when the request never got an answer (offline, timeout, server unreachable).
    var isNetworkProblem: Bool { self is URLError }
}
