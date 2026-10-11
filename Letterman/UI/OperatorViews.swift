import MapKit
import SwiftUI

struct ListingsView: View {
    @Environment(OperatorStore.self) private var store
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            HeroScreen {
                HStack(alignment: .firstTextBaseline) {
                    HeroTitle("My listings")
                    Spacer()
                    Button { creating = true } label: {
                        Label("New", systemImage: "plus").font(.fig(15, .bold)).foregroundStyle(Theme.gold)
                    }
                }
                Text(subtitle).font(.fig(15)).foregroundStyle(Theme.heroText)
            } content: {
                ForEach(upcoming) { listing in
                    NavigationLink(value: listing) { OpportunityCard(opportunity: listing, operatorView: true) }.buttonStyle(.plain)
                }
                if upcoming.isEmpty {
                    Text("No upcoming listings. Tap New to post an opportunity volunteers can sign up for.")
                        .font(.fig(16)).foregroundStyle(Theme.mute).card(padding: 18)
                }
                if !past.isEmpty {
                    SectionHeader("Past")
                    ForEach(past) { listing in
                        NavigationLink(value: listing) { OpportunityCard(opportunity: listing, operatorView: true) }
                            .buttonStyle(.plain).opacity(0.7)
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Opportunity.self) { ListingDetailView(listingID: $0.id) }
            .sheet(isPresented: $creating) { ListingFormView(existing: nil) }
            .errorAlert($error)
        }
    }

    private var upcoming: [Opportunity] { store.listings.filter { $0.endsAt >= Date() }.sorted { $0.startsAt < $1.startsAt } }
    private var past: [Opportunity] { store.listings.filter { $0.endsAt < Date() } }

    private var subtitle: String {
        if upcoming.isEmpty { return "Post opportunities and see who signs up." }
        let needed = upcoming.reduce(0) { $0 + $1.spotsLeft }
        if needed == 0 { return "All upcoming spots are filled." }
        return "\(needed) more \(needed == 1 ? "volunteer" : "volunteers") needed across your upcoming listings"
    }

    private func load() async {
        do { try await store.load() } catch { self.error = error.localizedDescription }
    }
}

struct ListingDetailView: View {
    @Environment(OperatorStore.self) private var store
    let listingID: String
    @State private var editing = false
    @State private var error: String?

    var body: some View {
        if let listing = store.listings.first(where: { $0.id == listingID }) {
            content(listing)
        } else {
            ContentUnavailableView("Listing deleted", systemImage: "trash")
        }
    }

    private func content(_ l: Opportunity) -> some View {
        let people = store.attendees[l.id] ?? []
        return HeroScreen {
            HeroTitle(l.title, size: 42)
            Text("\(l.startsAt.dayAndTime), \(l.address)").font(.fig(15)).foregroundStyle(Theme.heroText)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(l.spotsFilled)").font(.display(96)).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("of \(l.spotsNeeded) signed up").font(.fig(18, .bold))
                    Text(l.spotsLeft == 0 ? "You have everyone you need" : "\(l.spotsLeft) more \(l.spotsLeft == 1 ? "volunteer" : "volunteers") needed")
                        .font(.fig(15)).foregroundStyle(Theme.heroText)
                }
            }
            .accessibilityElement(children: .combine)
            Seats(filled: l.spotsFilled, total: l.spotsNeeded)
        } content: {
            SectionHeader("Who's coming")
            if people.isEmpty {
                Text("Nobody has signed up yet. Pull down to refresh.").font(.fig(15)).foregroundStyle(Theme.mute).card()
            }
            ForEach(people) { AttendeeRow(signup: $0) }
        }
        .refreshable { await loadAttendees(l) }
        .task { await loadAttendees(l) }
        .navigationBarTitleDisplayMode(.inline)
        .forestNavBar()
        .toolbar { Button("Edit") { editing = true }.foregroundStyle(Theme.gold) }
        .sheet(isPresented: $editing) { ListingFormView(existing: l) }
        .errorAlert($error)
    }

    private func loadAttendees(_ listing: Opportunity) async {
        do { try await store.loadAttendees(for: listing) } catch { self.error = error.localizedDescription }
    }
}

/// One circle per spot: gold when taken. Collapses to a bar for big events.
struct Seats: View {
    let filled: Int
    let total: Int

    var body: some View {
        Group {
            if total <= 12 {
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(i < filled ? Theme.gold : .clear)
                            .overlay(Circle().inset(by: 3).strokeBorder(i < filled ? Theme.forest : Theme.heroMuted,
                                                                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                            .overlay(Circle().strokeBorder(i < filled ? Theme.gold : Theme.heroMuted, lineWidth: 2))
                            .frame(width: 26, height: 26)
                    }
                }
            } else {
                GoalTrack(progress: Double(filled) / Double(max(total, 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct AttendeeRow: View {
    let signup: Signup

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(signup.name).font(.fig(16, .bold)).foregroundStyle(Theme.ink)
                let schoolLine = [signup.school, signup.grade.isEmpty ? "" : "grade \(signup.grade)"].filter { !$0.isEmpty }.joined(separator: ", ")
                if !schoolLine.isEmpty { Text(schoolLine).font(.fig(13)).foregroundStyle(Theme.mute) }
                Text(signup.email).font(.fig(13)).foregroundStyle(Theme.mute).textSelection(.enabled)
                if !signup.phone.isEmpty { Text(signup.phone).font(.fig(13)).foregroundStyle(Theme.mute).textSelection(.enabled) }
            }
            Spacer()
            if let tel = URL(string: "tel:\(signup.phone.filter { $0.isNumber || $0 == "+" })"), !signup.phone.isEmpty {
                contact(tel, "phone.fill", "Call \(signup.name)")
            }
            if let mail = URL(string: "mailto:\(signup.email)") {
                contact(mail, "envelope.fill", "Email \(signup.name)")
            }
        }
        .card()
    }

    private func contact(_ url: URL, _ icon: String, _ label: String) -> some View {
        Link(destination: url) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.link)
                .frame(width: 40, height: 40).background(Theme.chalk, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(label)
    }
}

struct ListingFormView: View {
    @Environment(OperatorStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let existing: Opportunity?
    @State private var title = ""
    @State private var orgName = ""
    @State private var details = ""
    @State private var address = ""
    @State private var startsAt = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!)!
    @State private var hours = 2.0
    @State private var spots = 5
    // Set only by picking an Apple Maps suggestion, so the map position always matches the address.
    @State private var lat: Double?
    @State private var lng: Double?
    @State private var pickedAddress: String?
    @State private var completer = AddressCompleter()
    @State private var busy = false
    @State private var confirmingDelete = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    TextField("Title, e.g. Saturday pantry shift", text: $title)
                    TextField("Organization name", text: $orgName)
                    TextField("What volunteers will do (optional)", text: $details, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    TextField("Start typing the address", text: $address)
                        .textContentType(.fullStreetAddress)
                        .onChange(of: address) { _, typed in addressEdited(typed) }
                    ForEach(lat == nil ? completer.suggestions : [], id: \.self) { suggestion in
                        Button { pick(suggestion) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title).foregroundStyle(Theme.ink)
                                Text(suggestion.subtitle).font(.fig(13)).foregroundStyle(Theme.mute)
                            }
                        }
                    }
                    DatePicker("Starts", selection: $startsAt, in: Date()...)
                    Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                        HStack { Text("Hours"); Spacer(); Text(hours.hoursText).foregroundStyle(Theme.ink) }
                    }
                } header: {
                    Text("Where and when")
                } footer: {
                    if lat == nil && !address.trimmed.isEmpty {
                        Text("Pick an address from the suggestions so students nearby can find this.")
                    }
                }
                Section {
                    Stepper(value: $spots, in: max(existing?.spotsFilled ?? 1, 1)...1000) {
                        HStack { Text("Volunteers needed"); Spacer(); Text("\(spots)").foregroundStyle(Theme.ink) }
                    }
                } footer: {
                    if let existing, existing.spotsFilled > 0 {
                        Text("\(existing.spotsFilled) already signed up, so this can't go lower than that.")
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete listing", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("Deleting removes it from everyone's calendar in the app.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.chalk)
            .navigationTitle(existing == nil ? "New listing" : "Edit listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.link) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Post" : "Save") { Task { await save() } }.bold().tint(Theme.link).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this listing?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Everyone who signed up will lose their spot.")
            }
            .onAppear(perform: fill)
            .errorAlert($error)
        }
    }

    private var canSave: Bool {
        !busy && !title.trimmed.isEmpty && !orgName.trimmed.isEmpty && lat != nil
    }

    /// Typing after picking a suggestion means the saved map position no longer matches.
    private func addressEdited(_ typed: String) {
        guard typed != pickedAddress else { return }
        pickedAddress = nil
        lat = nil
        lng = nil
        completer.search(typed)
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        Task {
            do {
                let place = try await Geo.resolve(suggestion)
                pickedAddress = place.address
                address = place.address
                lat = place.location.coordinate.latitude
                lng = place.location.coordinate.longitude
                completer.clear()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func fill() {
        guard title.isEmpty else { return }
        if let e = existing {
            title = e.title
            orgName = e.orgName
            details = e.details
            if let location = e.location {
                pickedAddress = e.address
                lat = location.coordinate.latitude
                lng = location.coordinate.longitude
            }
            address = e.address
            startsAt = e.startsAt
            hours = e.durationHours
            spots = e.spotsNeeded
        } else {
            orgName = session.user?.orgName ?? ""
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await store.save([
                "title": title.trimmed, "org_name": orgName.trimmed, "description": details.trimmed,
                "address": address.trimmed, "starts_at": PBDate.string(startsAt),
                "duration_hours": hours, "spots_needed": spots, "lat": lat ?? 0, "lng": lng ?? 0,
            ], existingID: existing?.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let existing else { return }
        do {
            try await store.delete(existing)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
