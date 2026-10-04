import SwiftUI

struct HoursView: View {
    @Environment(Session.self) private var session
    @Environment(VolunteerStore.self) private var store
    @State private var showingNewLog = false
    @State private var exportURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            HeroScreen {
                hero
            } content: {
                SectionHeader(title: "Your logs") {
                    if !store.logs.isEmpty {
                        Button("Export") { export() }.font(.fig(15, .bold)).foregroundStyle(Theme.link)
                    }
                }
                ForEach(store.pending) { item in
                    PendingRow(item: item) { store.discardPending(item) }
                }
                ForEach(store.logs) { log in
                    NavigationLink(value: log) { LogRow(log: log) }.buttonStyle(.plain)
                }
                if store.logs.isEmpty && store.pending.isEmpty {
                    Text("No hours yet. After your next shift, tap + and hand your phone to the person in charge to sign.")
                        .font(.fig(16)).foregroundStyle(Theme.mute).card(padding: 18)
                }
            }
            .refreshable { await reload() }
            .overlay(alignment: .bottomTrailing) {
                Button { showingNewLog = true } label: {
                    Image(systemName: "plus").font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Theme.forest)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Theme.gold))
                        .overlay(Circle().strokeBorder(Theme.forest, lineWidth: 3))
                        .shadow(color: Theme.forest.opacity(0.35), radius: 9, y: 6)
                }
                .accessibilityLabel("Log hours")
                .padding(18)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HourLog.self) { LogDetailView(logID: $0.id) }
            .sheet(isPresented: $showingNewLog) { LogFormView(existing: nil) }
            .sheet(item: $exportURL) { ShareSheet(url: $0) }
            .errorAlert($error)
        }
    }

    @ViewBuilder private var hero: some View {
        let user = session.user
        let goal = user?.hoursGoal ?? 0
        let total = store.signedHours
        Text([user?.name, user?.school].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
            .font(.fig(15, .semibold)).foregroundStyle(Theme.heroText)
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(total.hoursText).font(.display(110)).foregroundStyle(Theme.gold).minimumScaleFactor(0.5)
            Text(goal > 0 ? "/ \(goal.hoursText) hrs" : "signed hrs").font(.display(38, relativeTo: .title))
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal > 0 ? "\(total.hoursText) of \(goal.hoursText) hours signed" : "\(total.hoursText) hours signed")
        if goal > 0 {
            Text(total >= goal ? "Goal reached. Nice work." : "\((goal - total).hoursText) hours to go to reach your goal")
                .font(.fig(15)).foregroundStyle(Theme.heroText)
            GoalTrack(progress: total / goal).padding(.top, 8)
        } else {
            Text("Only signed hours count. Set a goal in Profile to track progress.")
                .font(.fig(15)).foregroundStyle(Theme.heroText)
        }
    }

    private func reload() async {
        do { try await store.loadAll() } catch { self.error = error.localizedDescription }
    }

    private func export() {
        guard let user = session.user else { return }
        do {
            exportURL = try Export.spreadsheet(logs: store.logs, user: user)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Ten gold segments filling up toward the goal.
struct GoalTrack: View {
    let progress: Double

    var body: some View {
        let filled = Int((min(max(progress, 0), 1) * 10).rounded(.down))
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(i < filled ? Theme.gold : Theme.forest2).frame(height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

struct LogRow: View {
    let log: HourLog

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(log.placeName).font(.fig(16, .bold)).foregroundStyle(Theme.ink)
                Text(log.startedAt.dayAndTime).font(.fig(13)).foregroundStyle(Theme.mute)
                Group {
                    if log.isSigned { SignedPatch(signer: log.signerName) } else { NeedsSignatureBadge() }
                }
                .padding(.top, 4)
            }
            Spacer()
            HoursBadge(hours: log.hours)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct HoursBadge: View {
    let hours: Double

    var body: some View {
        VStack(spacing: 0) {
            Text(hours.hoursText).font(.display(34, relativeTo: .title)).foregroundStyle(Theme.ink)
            Text(hours == 1 ? "hour" : "hours").font(.fig(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.mute)
        }
        .frame(minWidth: 48)
    }
}

struct PendingRow: View {
    let item: PendingLog
    let discard: () -> Void
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.draft.placeName).font(.fig(16, .bold)).foregroundStyle(Theme.ink)
                Text(item.draft.startedAt.dayAndTime).font(.fig(13)).foregroundStyle(Theme.mute)
                if let problem = item.problem {
                    Text("Couldn't upload: \(problem)").font(.fig(13, .semibold)).foregroundStyle(Theme.felt)
                    Button("Discard this entry", role: .destructive) { confirming = true }.font(.fig(13, .bold))
                } else {
                    Label("Saved on your phone. Uploads when you're back online.", systemImage: "icloud.and.arrow.up")
                        .font(.fig(13, .semibold)).foregroundStyle(Theme.link)
                }
            }
            Spacer()
            HoursBadge(hours: item.draft.hours)
        }
        .card()
        .confirmationDialog("Discard this entry?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: discard)
        } message: {
            Text("It hasn't been uploaded, so it and any signature on it will be gone.")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
