import SwiftUI

struct AuthView: View {
    @Environment(Session.self) private var session
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var phone = ""
    @State private var school = ""
    @State private var grade = ""
    @State private var isOrganization = false
    @State private var orgName = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Letterman").font(.display(64)).foregroundStyle(Theme.gold).padding(.top, 40)
                Text(creating ? "Make an account to log hours and find places to volunteer."
                              : "Log volunteer hours, get them signed, and find your next shift.")
                    .font(.fig(16)).foregroundStyle(Theme.heroText)
                Stripe().padding(.vertical, 10)

                Picker("Mode", selection: $creating) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                if creating {
                    DarkField(label: "Full name", text: $name).textContentType(.name)
                }
                DarkField(label: "Email", text: $email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                DarkField(label: creating ? "Password (at least 8 characters)" : "Password", text: $password, secure: true)
                    .textContentType(creating ? .newPassword : .password)

                if creating {
                    DarkField(label: "Phone (optional, shared only with places you sign up for)", text: $phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    if !isOrganization {
                        DarkField(label: "School (optional)", text: $school)
                        DarkField(label: "Grade (optional)", text: $grade).keyboardType(.numberPad)
                    }
                    Toggle(isOn: $isOrganization) {
                        Text("I'm signing up for an organization that posts volunteer opportunities")
                            .font(.fig(15)).foregroundStyle(.white)
                    }
                    .tint(Theme.gold)
                    .padding(.vertical, 4)
                    if isOrganization {
                        DarkField(label: "Organization name", text: $orgName)
                        Text("Organization accounts are approved by hand. After you verify your email, the app shows how to ask for approval.")
                            .font(.fig(13)).foregroundStyle(Theme.heroMuted)
                    }
                }

                Button(creating ? "Create account" : "Sign in") { Task { await submit() } }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(busy || !canSubmit)
                    .opacity(busy || !canSubmit ? 0.6 : 1)
                    .padding(.top, 8)

                if !creating {
                    Button("Forgot password?") { Task { await resetPassword() } }
                        .font(.fig(15, .semibold))
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.forest.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .errorAlert($error)
        .alert("Check your email", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var canSubmit: Bool {
        let base = email.contains("@") && password.count >= (creating ? 8 : 1)
        return creating ? base && !name.trimmed.isEmpty && (!isOrganization || !orgName.trimmed.isEmpty) : base
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        do {
            if creating {
                try await session.signUp([
                    "name": name.trimmed,
                    "phone": phone.trimmed,
                    "school": isOrganization ? "" : school.trimmed,
                    "grade": isOrganization ? "" : grade.trimmed,
                    "operator_requested": isOrganization,
                    "org_name": isOrganization ? orgName.trimmed : "",
                ], email: email, password: password)
            } else {
                try await session.signIn(email: email, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resetPassword() async {
        guard email.contains("@") else {
            error = "Type your email above first, then tap Forgot password."
            return
        }
        do {
            try await session.requestPasswordReset(email: email)
            notice = "If an account exists for \(email.trimmed), we sent a link to reset the password."
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct VerifyEmailView: View {
    @Environment(Session.self) private var session
    let email: String
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check your email").font(.display(52)).foregroundStyle(Theme.gold)
            Text("We sent a link to \(email). Tap it to verify your account, then come back here.")
                .font(.fig(17)).foregroundStyle(Theme.heroText)
            Stripe().padding(.vertical, 8)
            Button("I've verified my email") { Task { await session.refresh() } }
                .buttonStyle(GoldButtonStyle())
            Button(sent ? "Sent. Check your inbox and spam folder." : "Send the email again") {
                Task {
                    do {
                        try await session.resendVerification()
                        sent = true
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
            .font(.fig(16, .semibold)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity).disabled(sent)
            Spacer()
            Button("Sign out") { session.signOut() }
                .font(.fig(16, .semibold)).foregroundStyle(Theme.heroMuted).frame(maxWidth: .infinity)
        }
        .padding(22)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.forest.ignoresSafeArea())
        .errorAlert($error)
    }
}

/// Shown to an organization account until the admin sets its role to operator in the dashboard.
struct AwaitingApprovalView: View {
    @Environment(Session.self) private var session
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Waiting for approval").font(.display(52)).foregroundStyle(Theme.gold)
            Text("Organization accounts are approved by hand. Email \(Config.supportEmail) to ask for \(user.orgName) to be approved, then come back here.")
                .font(.fig(17)).foregroundStyle(Theme.heroText)
                .textSelection(.enabled)
            Stripe().padding(.vertical, 8)
            Link("Email us to get approved", destination: mailURL)
                .buttonStyle(GoldButtonStyle())
            Button("I've been approved") { Task { await session.refresh() } }
                .font(.fig(16, .semibold)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity)
            Spacer()
            Button("Sign out") { session.signOut() }
                .font(.fig(16, .semibold)).foregroundStyle(Theme.heroMuted).frame(maxWidth: .infinity)
        }
        .padding(22)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.forest.ignoresSafeArea())
    }

    /// Opens a pre-filled email so the admin can find the account in the dashboard.
    private var mailURL: URL {
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = Config.supportEmail
        mail.queryItems = [
            URLQueryItem(name: "subject", value: "Approve my organization: \(user.orgName)"),
            URLQueryItem(name: "body", value: "Please approve my organization account.\n\nOrganization: \(user.orgName)\nAccount email: \(user.email)\n"),
        ]
        // Some mail apps turn a "+" (as in name+org@gmail.com) into a space.
        mail.percentEncodedQuery = mail.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return mail.url!
    }
}
