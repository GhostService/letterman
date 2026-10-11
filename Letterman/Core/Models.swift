import CoreLocation
import Foundation
import UIKit

// Mirrors the PocketBase collections in server/pb_migrations. Keys are snake_case on the server.

struct User: Codable, Equatable {
    let id: String
    var email: String
    var verified: Bool
    var name: String
    var phone: String
    var school: String
    var grade: String
    var role: String
    var operatorRequested: Bool
    var orgName: String
    var hoursGoal: Double

    var isOperator: Bool { role == "operator" }
    var awaitingOperatorApproval: Bool { operatorRequested && !isOperator }
}

struct AuthResponse: Decodable {
    let token: String
    let record: User
}

struct HourLog: Decodable, Identifiable, Equatable {
    let id: String
    var startedAt: Date
    var hours: Double
    var placeName: String
    var address: String
    var comments: String
    /// Base64 PNG. Empty until a supervisor signs.
    var signature: String
    var signerName: String
    /// Set by the server when signed. Kept as text because it's "" while unsigned.
    var signedAt: String
    /// The listing this was logged from, if the student signed up for it in the app. "" otherwise.
    var opportunity: String?
    /// Set by the server when the organization confirmed the student came; then there's no drawn signature.
    var confirmedBy: String?

    var isConfirmed: Bool { !(confirmedBy ?? "").isEmpty }
    var isSigned: Bool { !signature.isEmpty || isConfirmed }
    var signedDate: Date? { PBDate.parse(signedAt) }
    var signatureImage: UIImage? { Data(base64Encoded: signature).flatMap(UIImage.init(data:)) }
}

struct Opportunity: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    var `operator`: String
    var title: String
    var orgName: String
    var details: String
    var address: String
    var startsAt: Date
    var durationHours: Double
    var spotsNeeded: Int
    /// Added by the server on every read: how many volunteers have signed up.
    var spotsFilled: Int
    /// Map position of `address`, picked from Apple Maps suggestions when the listing is saved.
    var lat: Double?
    var lng: Double?

    var spotsLeft: Int { max(spotsNeeded - spotsFilled, 0) }
    var endsAt: Date { startsAt.addingTimeInterval(durationHours * 3600) }
    /// Nil for listings saved before locations existed. PocketBase sends 0 for an empty number field.
    var location: CLLocation? {
        guard let lat, let lng, lat != 0 || lng != 0 else { return nil }
        return CLLocation(latitude: lat, longitude: lng)
    }

    enum CodingKeys: String, CodingKey {
        case id, `operator`, title, orgName, address, startsAt, durationHours, spotsNeeded, spotsFilled, lat, lng
        case details = "description"
    }
}

struct Signup: Decodable, Identifiable, Equatable {
    let id: String
    var opportunity: String
    var volunteer: String
    var name: String
    var email: String
    var phone: String
    var school: String
    var grade: String
    /// The organization confirmed this volunteer came (which signed their hours).
    var attended: Bool?
    var expand: Expand?

    struct Expand: Decodable, Equatable {
        var opportunity: Opportunity?
    }
}

struct CalendarEvent: Decodable, Identifiable, Equatable {
    let id: String
    var title: String
    var startsAt: Date
    var durationHours: Double
    var location: String
    var notes: String
}

/// What the volunteer fills in on the log form. Also what waits in the outbox when offline.
struct LogDraft: Codable, Equatable {
    var placeName = ""
    var address = ""
    var startedAt = Date()
    var hours = 1.0
    var comments = ""
    var signaturePNG: Data?
    var signerName = ""
    /// The listing this log is for, when logged from a shift the student signed up for.
    var opportunity: String?

    init() {}

    /// Prefilled from a shift the student signed up for in the app.
    init(_ shift: Opportunity) {
        placeName = shift.orgName
        address = shift.address
        startedAt = shift.startsAt
        hours = shift.durationHours
        comments = shift.title
        opportunity = shift.id
    }

    init(_ log: HourLog) {
        placeName = log.placeName
        address = log.address
        startedAt = log.startedAt
        hours = log.hours
        comments = log.comments
    }

    func body(owner: String) -> [String: Any] {
        var body: [String: Any] = [
            "owner": owner,
            "place_name": placeName.trimmed,
            "address": address.trimmed,
            "started_at": PBDate.string(startedAt),
            "hours": hours,
            "comments": comments.trimmed,
        ]
        if let opportunity { body["opportunity"] = opportunity }
        if let signaturePNG {
            body["signature"] = signaturePNG.base64EncodedString()
            body["signer_name"] = signerName.trimmed
        }
        return body
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Double {
    /// 3 -> "3", 2.5 -> "2.5"
    var hoursText: String { formatted(.number.precision(.fractionLength(0...2))) }
}
