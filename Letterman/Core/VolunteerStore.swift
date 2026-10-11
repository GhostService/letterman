import Foundation
import Network
import Observation

/// Everything a volunteer sees: hour logs, opportunities, sign-ups and calendar entries.
@MainActor @Observable
final class VolunteerStore {
    let userID: String
    var logs: [HourLog] = []
    var pending: [PendingLog] = Outbox.load()
    var opportunities: [Opportunity] = []
    var signups: [Signup] = []
    var events: [CalendarEvent] = []

    private let pb = PocketBase.shared
    private let network = NWPathMonitor()
    private var uploading = false

    init(userID: String) {
        self.userID = userID
        // Upload waiting logs as soon as the phone gets a connection again.
        network.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.uploadPending() }
        }
        network.start(queue: .main)
    }

    deinit { network.cancel() }

    var signedHours: Double { logs.filter(\.isSigned).reduce(0) { $0 + $1.hours } }

    func signup(for opportunity: Opportunity) -> Signup? {
        signups.first { $0.opportunity == opportunity.id }
    }

    // MARK: Loading

    func loadAll() async throws {
        await uploadPending()
        async let logs: [HourLog] = pb.list("hour_logs", sort: "-started_at")
        async let opportunities: [Opportunity] = pb.list("opportunities", filter: "starts_at >= @now", sort: "starts_at")
        async let signups: [Signup] = pb.list("signups", filter: "volunteer = '\(userID)'", expand: "opportunity")
        async let events: [CalendarEvent] = pb.list("calendar_events", sort: "starts_at")
        (self.logs, self.opportunities, self.signups, self.events) = try await (logs, opportunities, signups, events)
        agendaChanged()
    }

    // MARK: Hour logs

    enum SaveResult { case uploaded, savedOffline }

    /// Creates a log, or updates an unsigned one. With no signal it goes to the outbox instead.
    func saveLog(_ draft: LogDraft, existingID: String? = nil) async throws -> SaveResult {
        do {
            try await upload(PendingLog(remoteID: existingID, draft: draft))
            return .uploaded
        } catch where error.isNetworkProblem {
            pending.append(PendingLog(remoteID: existingID, draft: draft))
            Outbox.save(pending)
            return .savedOffline
        }
    }

    func deleteLog(_ log: HourLog) async throws {
        try await pb.delete("hour_logs", id: log.id)
        logs.removeAll { $0.id == log.id }
    }

    func discardPending(_ item: PendingLog) {
        pending.removeAll { $0.id == item.id }
        Outbox.save(pending)
    }

    /// Uploads waiting logs in order. Stops quietly while offline. An item the server refuses stays
    /// (with the reason) until the volunteer discards it, so a signature is never silently dropped.
    func uploadPending() async {
        // One upload pass at a time, or the same entry could be sent twice.
        guard !uploading else { return }
        uploading = true
        defer { uploading = false }
        for item in pending {
            do {
                try await upload(item)
                pending.removeAll { $0.id == item.id }
            } catch where error.isNetworkProblem {
                return
            } catch {
                if let i = pending.firstIndex(where: { $0.id == item.id }) {
                    pending[i].problem = error.localizedDescription
                }
            }
            Outbox.save(pending)
        }
    }

    private func upload(_ item: PendingLog) async throws {
        var body = item.draft.body(owner: userID)
        let saved: HourLog
        if let id = item.remoteID {
            saved = try await pb.update("hour_logs", id: id, body)
        } else {
            body["id"] = item.recordID
            do {
                saved = try await pb.create("hour_logs", body)
            } catch let error as APIError where error.status == 400 {
                // An earlier try may have reached the server even though the reply never came back.
                guard let existing: HourLog = try? await pb.send("GET", "/api/collections/hour_logs/records/\(item.recordID)")
                else { throw error }
                saved = existing
            }
        }
        logs.removeAll { $0.id == saved.id }
        logs.append(saved)
        logs.sort { $0.startedAt > $1.startedAt }
    }

    // MARK: Opportunities

    func signUp(for opportunity: Opportunity) async throws {
        let signup: Signup = try await pb.send("POST", "/api/collections/signups/records",
                                               query: [URLQueryItem(name: "expand", value: "opportunity")],
                                               body: ["opportunity": opportunity.id, "volunteer": userID])
        signups.append(signup)
        try await reloadOpportunity(opportunity.id)
    }

    func cancel(_ signup: Signup) async throws {
        try await pb.delete("signups", id: signup.id)
        signups.removeAll { $0.id == signup.id }
        try await reloadOpportunity(signup.opportunity)
    }

    private func reloadOpportunity(_ id: String) async throws {
        let fresh: Opportunity = try await pb.send("GET", "/api/collections/opportunities/records/\(id)")
        if let i = opportunities.firstIndex(where: { $0.id == id }) { opportunities[i] = fresh }
        if let i = signups.firstIndex(where: { $0.opportunity == id }) { signups[i].expand = .init(opportunity: fresh) }
        agendaChanged()
    }

    // MARK: Shifts to log

    static let dismissedShiftsKey = "dismissedShiftLogs"
    private(set) var dismissedShifts = UserDefaults.standard.stringArray(forKey: dismissedShiftsKey) ?? []

    /// Signed-up shifts that ended in the last 60 days and haven't been logged (or waved off) yet.
    var unloggedShifts: [Opportunity] {
        let now = Date()
        let logged = Set(logs.compactMap(\.opportunity) + pending.compactMap(\.draft.opportunity))
        return signups.compactMap(\.expand?.opportunity)
            .filter { $0.endsAt < now && $0.endsAt > now.addingTimeInterval(-60 * 86400) }
            .filter { !logged.contains($0.id) && !dismissedShifts.contains($0.id) }
            .sorted { $0.startsAt > $1.startsAt }
    }

    func dismissShift(_ shift: Opportunity) {
        dismissedShifts.append(shift.id)
        UserDefaults.standard.set(dismissedShifts, forKey: Self.dismissedShiftsKey)
    }

    // MARK: Calendar

    /// Keeps the iPhone Calendar copy and the reminders in step with the agenda.
    private func agendaChanged() {
        CalendarSync.sync(agenda)
        Reminders.sync(agenda)
    }

    func saveEvent(_ body: [String: Any], existingID: String?) async throws {
        var body = body
        body["owner"] = userID
        let saved: CalendarEvent = existingID == nil
            ? try await pb.create("calendar_events", body)
            : try await pb.update("calendar_events", id: existingID!, body)
        events.removeAll { $0.id == saved.id }
        events.append(saved)
        events.sort { $0.startsAt < $1.startsAt }
        agendaChanged()
    }

    func deleteEvent(_ event: CalendarEvent) async throws {
        try await pb.delete("calendar_events", id: event.id)
        events.removeAll { $0.id == event.id }
        agendaChanged()
    }

    /// Custom entries plus every opportunity the volunteer signed up for, oldest first.
    var agenda: [AgendaItem] {
        let fromSignups = signups.compactMap { s in s.expand?.opportunity.map(AgendaItem.init) }
        return (fromSignups + events.map(AgendaItem.init)).sorted { $0.start < $1.start }
    }
}

struct AgendaItem: Identifiable, Equatable {
    enum Kind: Equatable { case signup(Opportunity), custom(CalendarEvent) }

    let id: String
    let title: String
    let location: String
    let notes: String
    let start: Date
    let hours: Double
    let kind: Kind

    var end: Date { start.addingTimeInterval(max(hours, 0.5) * 3600) }

    init(_ o: Opportunity) {
        id = "opp-" + o.id
        title = o.title
        location = o.address
        notes = "\(o.orgName)\n\(o.details)".trimmed
        start = o.startsAt
        hours = o.durationHours
        kind = .signup(o)
    }

    init(_ e: CalendarEvent) {
        id = "evt-" + e.id
        title = e.title
        location = e.location
        notes = e.notes
        start = e.startsAt
        hours = e.durationHours
        kind = .custom(e)
    }
}
