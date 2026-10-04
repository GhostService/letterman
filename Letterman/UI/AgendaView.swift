import SwiftUI
import UIKit

struct AgendaView: View {
    @Environment(VolunteerStore.self) private var store
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var editing: EventEditor?
    @State private var syncOn = CalendarSync.isEnabled
    @State private var error: String?

    var body: some View {
        NavigationStack {
            HeroScreen {
                HStack(alignment: .firstTextBaseline) {
                    HeroTitle("Calendar")
                    Spacer()
                    Button { editing = EventEditor(event: nil, day: selectedDay) } label: {
                        Label("Add event", systemImage: "plus").font(.fig(15, .bold)).foregroundStyle(Theme.gold)
                    }
                }
                Text("Your sign-ups and your own volunteering plans.").font(.fig(15)).foregroundStyle(Theme.heroText)
            } content: {
                MonthCalendar(eventDays: eventDays, selected: $selectedDay)
                    .card(padding: 6)

                SectionHeader(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                let today = items(on: selectedDay)
                if today.isEmpty {
                    Text("Nothing on this day.").font(.fig(15)).foregroundStyle(Theme.mute).card()
                }
                ForEach(today) { row($0) }

                let upcoming = store.agenda.filter { $0.start > Date() && !Calendar.current.isDate($0.start, inSameDayAs: selectedDay) }.prefix(5)
                if !upcoming.isEmpty {
                    SectionHeader("Coming up")
                    ForEach(Array(upcoming)) { row($0) }
                }

                Toggle(isOn: $syncOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync to iPhone Calendar").font(.fig(16, .semibold)).foregroundStyle(Theme.ink)
                        Text("Adds a \"Volunteering\" calendar to the Calendar app.").font(.fig(13)).foregroundStyle(Theme.mute)
                    }
                }
                .tint(Theme.forest)
                .card()
                .padding(.top, 8)
            }
            .refreshable {
                do { try await store.loadAll() } catch { self.error = error.localizedDescription }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { EventFormView(editor: $0) }
            .onChange(of: syncOn) { _, on in Task { await setSync(on) } }
            .errorAlert($error)
        }
    }

    private var eventDays: Set<Day> { Set(store.agenda.map { Day($0.start) }) }

    private func items(on day: Date) -> [AgendaItem] {
        store.agenda.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    private func row(_ item: AgendaItem) -> some View {
        Button {
            if case .custom(let event) = item.kind { editing = EventEditor(event: event, day: event.startsAt) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(item.start.formatted(.dateTime.hour().minute())).font(.displayBold(18, relativeTo: .headline))
                    Text(item.start.formatted(.dateTime.month(.abbreviated).day())).font(.fig(11, .semibold)).foregroundStyle(Theme.mute)
                }
                .foregroundStyle(Theme.ink)
                .frame(width: 64, alignment: .trailing)
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.fig(16, .bold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                    if !item.location.isEmpty {
                        Text(item.location).font(.fig(13)).foregroundStyle(Theme.mute).multilineTextAlignment(.leading)
                    }
                    if case .signup = item.kind {
                        Text("Signed up through the app").font(.fig(11, .bold)).foregroundStyle(Theme.link)
                    } else {
                        Text("Your own event. Tap to edit.").font(.fig(11, .bold)).foregroundStyle(Color(hex: 0x9A6A00))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.card)
                .overlay(alignment: .leading) {
                    Rectangle().fill(item.kind.isSignup ? Theme.forest : Theme.gold).frame(width: 4)
                }
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 12, topTrailingRadius: 12))
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func setSync(_ on: Bool) async {
        if on {
            if await CalendarSync.enable() {
                CalendarSync.sync(store.agenda)
            } else {
                syncOn = false
                error = "Calendar access is off. Turn it on in Settings > Privacy & Security > Calendars > Letterman."
            }
        } else if CalendarSync.isEnabled {
            CalendarSync.disable()
        }
    }
}

extension AgendaItem.Kind {
    var isSignup: Bool { if case .signup = self { true } else { false } }
}

/// Native month calendar with a dot on days that have something planned.
struct MonthCalendar: UIViewRepresentable {
    var eventDays: Set<Day>
    @Binding var selected: Date

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = .current
        view.tintColor = UIColor(Theme.link)
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.selectedDate = Calendar.current.dateComponents([.year, .month, .day], from: selected)
        view.selectionBehavior = selection
        // Known before the first draw, so the first month shows its dots.
        context.coordinator.eventDays = eventDays
        return view
    }

    /// UICalendarView wants to be wider than the screen; make it fit the width SwiftUI offers
    /// and take the height it needs for that width (6 week rows when needed).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let width = proposal.width ?? 360
        let height = uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                    withHorizontalFittingPriority: .required,
                                                    verticalFittingPriority: .fittingSizeLevel).height
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let changed = context.coordinator.eventDays.symmetricDifference(eventDays)
        context.coordinator.eventDays = eventDays
        context.coordinator.selected = $selected
        if !changed.isEmpty { view.reloadDecorations(forDateComponents: changed.map(\.components), animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selected: $selected) }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var eventDays: Set<Day> = []
        var selected: Binding<Date>

        init(selected: Binding<Date>) { self.selected = selected }

        func calendarView(_ view: UICalendarView, decorationFor date: DateComponents) -> UICalendarView.Decoration? {
            guard let year = date.year, let month = date.month, let day = date.day else { return nil }
            return eventDays.contains(Day(year: year, month: month, day: day)) ? .default(color: UIColor(Theme.gold), size: .large) : nil
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate date: DateComponents?) {
            if let date, let day = Calendar.current.date(from: date) { selected.wrappedValue = day }
        }
    }
}

/// A calendar day. Used instead of DateComponents as a Set key: two DateComponents can be ==
/// yet hash differently (isLeapMonth false vs nil), which silently breaks Set lookups.
struct Day: Hashable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    var components: DateComponents { DateComponents(year: year, month: month, day: day) }
}

struct EventEditor: Identifiable {
    let id = UUID()
    let event: CalendarEvent?
    let day: Date
}

struct EventFormView: View {
    @Environment(VolunteerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editor: EventEditor
    @State private var title = ""
    @State private var startsAt = Date()
    @State private var hours = 1.0
    @State private var location = ""
    @State private var notes = ""
    @State private var busy = false
    @State private var error: String?

    init(editor: EventEditor) {
        self.editor = editor
        let e = editor.event
        _title = State(initialValue: e?.title ?? "")
        _startsAt = State(initialValue: e?.startsAt ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: editor.day) ?? editor.day)
        _hours = State(initialValue: e?.durationHours ?? 1)
        _location = State(initialValue: e?.location ?? "")
        _notes = State(initialValue: e?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you doing?", text: $title)
                    TextField("Where (optional)", text: $location)
                }
                Section {
                    DatePicker("Starts", selection: $startsAt)
                    Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                        HStack { Text("Hours"); Spacer(); Text(hours.hoursText).foregroundStyle(Theme.ink) }
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical).lineLimit(2...6)
                }
                if let event = editor.event {
                    Section {
                        Button("Delete event", role: .destructive) {
                            run { try await store.deleteEvent(event) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.chalk)
            .navigationTitle(editor.event == nil ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.link) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        run {
                            try await store.saveEvent([
                                "title": title.trimmed, "starts_at": PBDate.string(startsAt), "duration_hours": hours,
                                "location": location.trimmed, "notes": notes.trimmed,
                            ], existingID: editor.event?.id)
                        }
                    }
                    .bold()
                    .tint(Theme.link)
                    .disabled(title.trimmed.isEmpty || busy)
                }
            }
            .errorAlert($error)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            do {
                try await work()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
