import SwiftUI

@main
struct LettermanApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .font(.fig(17))
                .tint(Theme.link)
                .task { await session.restore() }
        }
    }
}

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isRestoring {
                Theme.forest.ignoresSafeArea()
            } else if let user = session.user {
                if !user.verified {
                    VerifyEmailView(email: user.email)
                } else if user.isOperator {
                    OperatorTabs(userID: user.id)
                } else if user.awaitingOperatorApproval {
                    AwaitingApprovalView(user: user)
                } else {
                    VolunteerTabs(userID: user.id)
                }
            } else {
                AuthView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Picks up email verification and operator approval when coming back to the app.
            if phase == .active, !session.isRestoring { Task { await session.refresh() } }
        }
        .background(KeyboardDismisser())
    }
}

/// Tapping anywhere outside a text field closes the keyboard, on every screen and sheet.
/// One tap recognizer on the app's window instead of a tap handler on each screen.
private struct KeyboardDismisser: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Hook() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class Hook: UIView, UIGestureRecognizerDelegate {
        override func didMoveToWindow() {
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === self }) else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false // the tap still reaches buttons, steppers and pickers
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        @objc private func tapped(_ tap: UITapGestureRecognizer) { tap.view?.endEditing(true) }

        // Tapping another text field moves the cursor there instead of closing the keyboard.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView { return false }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

struct VolunteerTabs: View {
    @State private var store: VolunteerStore
    @Environment(\.scenePhase) private var scenePhase

    init(userID: String) { _store = State(initialValue: VolunteerStore(userID: userID)) }

    var body: some View {
        TabView {
            HoursView().tabItem { Label("Hours", systemImage: "clock") }
            OpportunitiesView().tabItem { Label("Opportunities", systemImage: "hand.raised") }
            AgendaView().tabItem { Label("Calendar", systemImage: "calendar") }
            ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .environment(store)
        .task { try? await store.loadAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.uploadPending() } }
        }
    }
}

struct OperatorTabs: View {
    @State private var store: OperatorStore

    init(userID: String) { _store = State(initialValue: OperatorStore(userID: userID)) }

    var body: some View {
        TabView {
            ListingsView().tabItem { Label("My listings", systemImage: "list.bullet.rectangle") }
            ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .environment(store)
    }
}
