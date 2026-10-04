import SwiftUI

struct OpportunitiesView: View {
    @Environment(VolunteerStore.self) private var store
    @State private var onlyMine = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            HeroScreen {
                HeroTitle("Opportunities")
                Text(subtitle).font(.fig(15)).foregroundStyle(Theme.heroText)
            } content: {
                Picker("Show", selection: $onlyMine) {
                    Text("All upcoming").tag(false)
                    Text("Signed up").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                ForEach(shown) { opportunity in
                    NavigationLink(value: opportunity) {
                        OpportunityCard(opportunity: opportunity, going: store.signup(for: opportunity) != nil)
                    }
                    .buttonStyle(.plain)
                }
                if shown.isEmpty {
                    Text(onlyMine ? "You haven't signed up for anything yet. Find something in All upcoming."
                                  : "No upcoming opportunities right now. Pull down to check again.")
                        .font(.fig(16)).foregroundStyle(Theme.mute).card(padding: 18)
                }
            }
            .refreshable {
                do { try await store.loadAll() } catch { self.error = error.localizedDescription }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Opportunity.self) { OpportunityDetailView(opportunityID: $0.id) }
            .errorAlert($error)
        }
    }

    private var shown: [Opportunity] {
        onlyMine ? store.opportunities.filter { store.signup(for: $0) != nil } : store.opportunities
    }

    private var subtitle: String {
        let open = store.opportunities.filter { $0.spotsLeft > 0 }.count
        return open == 1 ? "1 opportunity with open spots" : "\(open) opportunities with open spots"
    }
}

struct OpportunityCard: View {
    let opportunity: Opportunity
    var going = false
    /// Operators see "5 of 8 signed up" instead of "3 spots left".
    var operatorView = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(opportunity.startsAt.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.fig(13, .semibold)).foregroundStyle(Theme.gold)
                Text(opportunity.startsAt.formatted(.dateTime.day())).font(.display(38, relativeTo: .title))
                Text(opportunity.startsAt.formatted(.dateTime.month(.abbreviated)))
                    .font(.fig(13, .semibold)).foregroundStyle(Theme.gold)
            }
            .foregroundStyle(.white)
            .frame(width: 70)
            .frame(maxHeight: .infinity)
            .background(Theme.forest)

            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.title).font(.fig(17, .bold)).foregroundStyle(Theme.ink)
                Text("\(opportunity.orgName), \(opportunity.address)").font(.fig(13)).foregroundStyle(Theme.mute)
                Text("\(opportunity.startsAt.formatted(date: .omitted, time: .shortened)) for \(opportunity.durationHours.hoursText) \(opportunity.durationHours == 1 ? "hour" : "hours")")
                    .font(.fig(13)).foregroundStyle(Theme.mute)
                HStack(alignment: .firstTextBaseline) {
                    if operatorView {
                        Text("\(opportunity.spotsFilled)").font(.display(22, relativeTo: .title3)).foregroundStyle(Theme.link)
                        + Text(" of \(opportunity.spotsNeeded) signed up").font(.fig(12, .semibold)).foregroundStyle(Theme.mute)
                    } else {
                        Text("\(opportunity.spotsLeft)").font(.display(22, relativeTo: .title3))
                            .foregroundStyle(opportunity.spotsLeft <= 1 ? Theme.felt : Theme.link)
                        + Text(" of \(opportunity.spotsNeeded) spots left").font(.fig(12, .semibold)).foregroundStyle(Theme.mute)
                    }
                    Spacer()
                    if !operatorView { pill }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var pill: some View {
        if going {
            Text("You're going").font(.fig(13, .bold)).foregroundStyle(Theme.gold)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Theme.forest))
        } else if opportunity.spotsLeft == 0 {
            Text("Full").font(.fig(13, .bold)).foregroundStyle(Theme.mute)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().strokeBorder(Theme.mute))
        } else {
            Text("Sign up").font(.fig(13, .bold)).foregroundStyle(Theme.forest)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Theme.gold))
        }
    }
}

struct OpportunityDetailView: View {
    @Environment(VolunteerStore.self) private var store
    let opportunityID: String
    @State private var busy = false
    @State private var confirmingCancel = false
    @State private var error: String?

    var body: some View {
        if let opportunity = store.opportunities.first(where: { $0.id == opportunityID }) {
            content(opportunity)
        } else {
            ContentUnavailableView("This opportunity was removed", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func content(_ o: Opportunity) -> some View {
        let signup = store.signup(for: o)
        return HeroScreen {
            Text(o.orgName).font(.fig(15, .semibold)).foregroundStyle(Theme.heroText)
            HeroTitle(o.title, size: 46)
            Text(o.startsAt.dayAndTime).font(.fig(16, .semibold))
            Text("\(o.durationHours.hoursText) \(o.durationHours == 1 ? "hour" : "hours"), until \(o.endsAt.formatted(date: .omitted, time: .shortened))")
                .font(.fig(15)).foregroundStyle(Theme.heroText)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(o.spotsLeft)").font(.display(72)).foregroundStyle(Theme.gold)
                Text("of \(o.spotsNeeded) spots left").font(.fig(16, .semibold))
            }
            .accessibilityElement(children: .combine)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where").font(.fig(13, .semibold)).foregroundStyle(Theme.mute)
                Text(o.address).font(.fig(16)).foregroundStyle(Theme.ink)
                if let maps = URL(string: "https://maps.apple.com/?q=\(o.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Link("Open in Maps", destination: maps).font(.fig(15, .bold))
                }
            }
            .card()
            if !o.details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("About").font(.fig(13, .semibold)).foregroundStyle(Theme.mute)
                    Text(o.details).font(.fig(16)).foregroundStyle(Theme.ink)
                }
                .card()
            }

            if let signup {
                VStack(alignment: .leading, spacing: 10) {
                    Label("You're signed up. It's on your calendar.", systemImage: "checkmark.seal.fill")
                        .font(.fig(16, .bold)).foregroundStyle(Theme.link)
                    Text("\(o.orgName) can see your name, email, and the phone, school and grade on your profile.")
                        .font(.fig(13)).foregroundStyle(Theme.mute)
                    Button("Cancel my spot", role: .destructive) { confirmingCancel = true }
                        .font(.fig(16, .semibold)).disabled(busy)
                }
                .card()
                .confirmationDialog("Cancel your spot?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                    Button("Cancel my spot", role: .destructive) { run { try await store.cancel(signup) } }
                    Button("Keep it", role: .cancel) {}
                }
            } else if o.spotsLeft > 0 {
                Button("Sign up") { run { try await store.signUp(for: o) } }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(busy)
                Text("\(o.orgName) will see your name, email, and the phone, school and grade on your profile so they can reach you.")
                    .font(.fig(13)).foregroundStyle(Theme.mute).padding(.horizontal, 4)
            } else {
                Text("This one is full.").font(.fig(16, .semibold)).foregroundStyle(Theme.mute).card()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .forestNavBar()
        .errorAlert($error)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }
}
