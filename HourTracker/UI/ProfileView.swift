import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session
    @State private var name = ""
    @State private var phone = ""
    @State private var school = ""
    @State private var grade = ""
    @State private var orgName = ""
    @State private var goal = 0.0
    @State private var busy = false
    @State private var saved = false
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var error: String?

    var body: some View {
        let user = session.user
        NavigationStack {
            HeroScreen {
                HeroTitle(user?.name ?? "Profile", size: 46)
                Text(user?.email ?? "").font(.fig(15)).foregroundStyle(Theme.heroText)
                if user?.isOperator == true {
                    Text("Organization account").font(.fig(13, .bold)).foregroundStyle(Theme.gold)
                }
            } content: {
                if user?.awaitingOperatorApproval == true {
                    Label("Your organization account is waiting for approval. Until then you can use the app as a volunteer.",
                          systemImage: "hourglass")
                        .font(.fig(14, .semibold)).foregroundStyle(Theme.ink).card()
                }

                VStack(alignment: .leading, spacing: 12) {
                    field("Full name", $name)
                    field("Phone (optional)", $phone).keyboardType(.phonePad)
                    if user?.isOperator == true {
                        field("Organization name", $orgName)
                    } else {
                        field("School (optional)", $school)
                        field("Grade (optional)", $grade).keyboardType(.numberPad)
                        Stepper(value: $goal, in: 0...1000, step: 5) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hours goal").font(.fig(13, .semibold)).foregroundStyle(Theme.mute)
                                Text(goal == 0 ? "No goal" : "\(goal.hoursText) hours").font(.fig(17)).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                    Button(saved ? "Saved" : "Save changes") { Task { await save() } }
                        .buttonStyle(ForestButtonStyle())
                        .disabled(busy || name.trimmed.isEmpty)
                }
                .card()

                Text("Your phone, school and grade are only shared with organizations whose opportunities you sign up for. Personal details are encrypted on the server.")
                    .font(.fig(13)).foregroundStyle(Theme.mute).padding(.horizontal, 4)

                Button("Sign out") { confirmingSignOut = true }
                    .buttonStyle(ForestButtonStyle()).padding(.top, 12)
                Button("Delete my account", role: .destructive) { confirmingDelete = true }
                    .font(.fig(16, .semibold)).frame(maxWidth: .infinity).padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: loadFields)
            .onChange(of: session.user) { _, _ in loadFields() }
            .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { session.signOut() }
            } message: {
                Text(Outbox.load().isEmpty ? "You can sign back in any time."
                     : "You have hour logs that haven't uploaded yet. Signing out deletes them from this phone.")
            }
            .alert("Delete your account?", isPresented: $confirmingDelete) {
                Button("Delete everything", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, all your hour logs and signatures, your sign-ups and your calendar entries. Export your hours first if you need them.")
            }
            .errorAlert($error)
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.fig(13, .semibold)).foregroundStyle(Theme.mute)
            TextField(label, text: text).font(.fig(17)).foregroundStyle(Theme.ink)
            Divider()
        }
    }

    private func loadFields() {
        guard let user = session.user else { return }
        name = user.name
        phone = user.phone
        school = user.school
        grade = user.grade
        orgName = user.orgName
        goal = user.hoursGoal
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await session.updateProfile([
                "name": name.trimmed, "phone": phone.trimmed, "school": school.trimmed,
                "grade": grade.trimmed, "org_name": orgName.trimmed, "hours_goal": goal,
            ])
            saved = true
            try? await Task.sleep(for: .seconds(2))
            saved = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        do { try await session.deleteAccount() } catch { self.error = error.localizedDescription }
    }
}
