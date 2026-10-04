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
                Text("Hour Tracker").font(.display(64)).foregroundStyle(Theme.gold).padding(.top, 40)
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
                        Text("An admin reviews organization accounts before they can post. Until then you can use the app as a volunteer.")
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
