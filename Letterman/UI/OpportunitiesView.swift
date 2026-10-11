import CoreLocation
import SwiftUI

struct OpportunitiesView: View {
    @Environment(VolunteerStore.self) private var store
    @State private var onlyMine = false
    @State private var choosingArea = false
    @State private var error: String?
    @AppStorage(AreaKey.name) private var areaName = ""
    @AppStorage(AreaKey.lat) private var areaLat = 0.0
    @AppStorage(AreaKey.lng) private var areaLng = 0.0
    @AppStorage(AreaKey.radius) private var radiusMiles = 25

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

                if !onlyMine { areaRow }

                ForEach(shown) { opportunity in
                    NavigationLink(value: opportunity) {
                        OpportunityCard(opportunity: opportunity, going: store.signup(for: opportunity) != nil,
                                        distance: distance(to: opportunity))
                    }
                    .buttonStyle(.plain)
                }
                if shown.isEmpty {
                    Text(emptyMessage).font(.fig(16)).foregroundStyle(Theme.mute).card(padding: 18)
                }
            }
            .refreshable {
                do { try await store.loadAll() } catch { self.error = error.localizedDescription }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Opportunity.self) { OpportunityDetailView(opportunityID: $0.id) }
            .sheet(isPresented: $choosingArea) { AreaSheet() }
            .errorAlert($error)
        }
    }

    private var areaRow: some View {
        Button { choosingArea = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.link)
                Text(center == nil ? "Showing everywhere"
                     : radiusMiles == 0 ? "Any distance from \(areaName)" : "Within \(radiusMiles) mi of \(areaName)")
                    .font(.fig(15, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(center == nil ? "Set your area" : "Change").font(.fig(15, .bold)).foregroundStyle(Theme.link)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var center: CLLocation? {
        areaName.isEmpty ? nil : CLLocation(latitude: areaLat, longitude: areaLng)
    }

    private func distance(to opportunity: Opportunity) -> Double? {
        guard let center, let location = opportunity.location else { return nil }
        return Geo.miles(center, location)
    }

    // ponytail: filters every upcoming listing on the phone; fine for hundreds. At thousands, add a
    // lat/lng bounding box to the opportunities query in VolunteerStore.loadAll.
    private var nearby: [Opportunity] {
        guard center != nil, radiusMiles > 0 else { return store.opportunities }
        // Listings saved before locations existed can't be ruled out, so they stay.
        return store.opportunities.filter { distance(to: $0).map { $0 <= Double(radiusMiles) } ?? true }
    }

    private var shown: [Opportunity] {
        onlyMine ? store.opportunities.filter { store.signup(for: $0) != nil } : nearby
    }

    private var emptyMessage: String {
        if onlyMine { return "You haven't signed up for anything yet. Find something in All upcoming." }
        if !store.opportunities.isEmpty { return "Nothing within \(radiusMiles) mi of \(areaName). Try a bigger distance." }
        return "No upcoming opportunities right now. Pull down to check again."
    }

    private var subtitle: String {
        let open = nearby.filter { $0.spotsLeft > 0 }.count
        return open == 1 ? "1 opportunity with open spots" : "\(open) opportunities with open spots"
    }
}

/// Where "near me" is measured from, and how far. Saved on this phone only.
struct AreaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AreaKey.name) private var areaName = ""
    @AppStorage(AreaKey.lat) private var areaLat = 0.0
    @AppStorage(AreaKey.lng) private var areaLng = 0.0
    @AppStorage(AreaKey.radius) private var radiusMiles = 25
    @State private var place = ""
    @State private var radius = 25
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ZIP code or town", text: $place)
                    Button { Task { await useMyLocation() } } label: {
                        Label("Use my location", systemImage: "location.fill")
                    }
                    .disabled(busy)
                } header: {
                    Text("Near")
                } footer: {
                    Text("Saved on this phone only. Your location is never sent to Letterman's server.")
                }
                Section("Distance") {
                    Picker("Distance", selection: $radius) {
                        ForEach([5, 10, 25, 50], id: \.self) { Text("\($0) mi").tag($0) }
                        Text("Any").tag(0)
                    }
                    .pickerStyle(.segmented)
                }
                if !areaName.isEmpty {
                    Section {
                        Button("Show everywhere", role: .destructive) {
                            areaName = ""
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.chalk)
            .navigationTitle("Your area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.link) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.bold().tint(Theme.link)
                        .disabled(busy || place.trimmed.isEmpty)
                }
            }
            .onAppear {
                place = areaName
                radius = radiusMiles
            }
            .errorAlert($error)
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            // Unchanged (including "your location") means the saved coordinates still apply.
            if place.trimmed != areaName { setArea(place.trimmed, try await Geo.find(place.trimmed)) }
            radiusMiles = radius
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func useMyLocation() async {
        busy = true
        defer { busy = false }
        do {
            setArea("your location", try await Geo.currentLocation())
            radiusMiles = radius
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setArea(_ name: String, _ location: CLLocation) {
        areaLat = location.coordinate.latitude
        areaLng = location.coordinate.longitude
        areaName = name
    }
}

struct OpportunityCard: View {
    let opportunity: Opportunity
    var going = false
    /// Miles from the volunteer's area, when they've set one.
    var distance: Double?
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
                Text("\(opportunity.orgName), \(opportunity.address)" + (distance.map { " · \($0.formatted(.number.precision(.fractionLength(0...1)))) mi" } ?? ""))
                    .font(.fig(13)).foregroundStyle(Theme.mute)
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
