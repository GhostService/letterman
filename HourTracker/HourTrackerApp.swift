import SwiftUI

@main
struct HourTrackerApp: App {
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
    }
}

struct VolunteerTabs: View {
    @State private var store: VolunteerStore

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
