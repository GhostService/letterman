import Foundation
import Observation

/// An operator's own listings and who signed up for each.
@MainActor @Observable
final class OperatorStore {
    let userID: String
    var listings: [Opportunity] = []
    var attendees: [String: [Signup]] = [:]

    private let pb = PocketBase.shared

    init(userID: String) { self.userID = userID }

    func load() async throws {
        listings = try await pb.list("opportunities", filter: "operator = '\(userID)'", sort: "-starts_at")
    }

    func loadAttendees(for listing: Opportunity) async throws {
        attendees[listing.id] = try await pb.list("signups", filter: "opportunity = '\(listing.id)'", sort: "created")
        // Refresh the count too, in case people signed up since the list loaded.
        let fresh: Opportunity = try await pb.send("GET", "/api/collections/opportunities/records/\(listing.id)")
        if let i = listings.firstIndex(where: { $0.id == fresh.id }) { listings[i] = fresh }
    }

    func save(_ body: [String: Any], existingID: String?) async throws {
        var body = body
        body["operator"] = userID
        let saved: Opportunity = existingID == nil
            ? try await pb.create("opportunities", body)
            : try await pb.update("opportunities", id: existingID!, body)
        listings.removeAll { $0.id == saved.id }
        listings.append(saved)
        listings.sort { $0.startsAt > $1.startsAt }
    }

    func delete(_ listing: Opportunity) async throws {
        try await pb.delete("opportunities", id: listing.id)
        listings.removeAll { $0.id == listing.id }
    }
}
