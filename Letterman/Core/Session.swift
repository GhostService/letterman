import Foundation
import Observation

/// Who is signed in. Owns the login token and the signed-in user's profile.
@MainActor @Observable
final class Session {
    private(set) var user: User?
    private(set) var isRestoring = true

    private let pb = PocketBase.shared
    private static let tokenKey = "pb-token"
    private static let userKey = "pb-user"

    /// On launch: reuse the saved login and refresh it. Works offline with the cached profile,
    /// so hours can still be logged (they wait in the outbox) with no signal.
    func restore() async {
        defer { isRestoring = false }
        guard let token = Keychain.get(Self.tokenKey).flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        pb.token = token
        user = Keychain.get(Self.userKey).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
        await refresh()
    }

    /// Gets a fresh token and profile (e.g. after verifying email or being approved as an operator).
    func refresh() async {
        guard pb.token != nil else { return }
        do {
            let auth: AuthResponse = try await pb.send("POST", "/api/collections/users/auth-refresh")
            store(auth)
        } catch let error as APIError where error.status == 401 || error.status == 403 || error.status == 404 {
            signOut() // Token expired or account deleted.
        } catch {
            // Offline: keep using the cached profile.
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            let auth: AuthResponse = try await pb.send("POST", "/api/collections/users/auth-with-password",
                                                       body: ["identity": email.trimmed, "password": password])
            store(auth)
        } catch let error as APIError where error.status == 400 {
            throw APIError(status: 400, message: "That email and password don't match. Check them, or tap Forgot password.")
        }
    }

    func signUp(_ fields: [String: Any], email: String, password: String) async throws {
        var body = fields
        body["email"] = email.trimmed
        body["password"] = password
        body["passwordConfirm"] = password
        // The reply is ignored: before sign-in the server hides fields like email from it.
        let _: Empty = try await pb.send("POST", "/api/collections/users/records", body: body)
        try await signIn(email: email, password: password)
        // The verify screen has a "Resend" button if this email doesn't go out.
        try? await resendVerification()
    }

    func resendVerification() async throws {
        guard let email = user?.email else { return }
        let _: Empty = try await pb.send("POST", "/api/collections/users/request-verification", body: ["email": email])
    }

    func requestPasswordReset(email: String) async throws {
        let _: Empty = try await pb.send("POST", "/api/collections/users/request-password-reset", body: ["email": email.trimmed])
    }

    func updateProfile(_ fields: [String: Any]) async throws {
        guard let id = user?.id else { return }
        let updated: User = try await pb.update("users", id: id, fields)
        user = updated
        cacheUser()
    }

    /// Permanently deletes the account and everything in it on the server.
    func deleteAccount() async throws {
        guard let id = user?.id else { return }
        try await pb.delete("users", id: id)
        signOut()
    }

    func signOut() {
        pb.token = nil
        user = nil
        Keychain.delete(Self.tokenKey)
        Keychain.delete(Self.userKey)
        Outbox.clear()
        CalendarSync.disable()
    }

    private func store(_ auth: AuthResponse) {
        pb.token = auth.token
        user = auth.record
        Keychain.set(Data(auth.token.utf8), for: Self.tokenKey)
        cacheUser()
    }

    private func cacheUser() {
        if let user, let data = try? JSONEncoder().encode(user) { Keychain.set(data, for: Self.userKey) }
    }
}
