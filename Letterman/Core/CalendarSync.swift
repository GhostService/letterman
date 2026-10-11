import EventKit
import Foundation

/// Copies the volunteer's agenda into a "Volunteering" calendar in the iPhone Calendar app.
/// The app only ever touches that one calendar, never the user's own.
@MainActor
enum CalendarSync {
    private static let store = EKEventStore()
    private static let enabledKey = "calendarSyncEnabled"
    private static let calendarIDKey = "calendarSyncCalendarID"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks for Calendar access. Returns false if the user said no.
    static func enable() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        return granted
    }

    /// Turns syncing off and removes the "Volunteering" calendar.
    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess, let calendar = existingCalendar() {
            try? store.removeCalendar(calendar, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: calendarIDKey)
    }

    // ponytail: replace-all sync of upcoming events; simple and can't drift. Fine for a few hundred events.
    static func sync(_ agenda: [AgendaItem]) {
        guard isEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = existingCalendar() ?? makeCalendar() else { return }

        let from = Calendar.current.startOfDay(for: Date())
        let to = Calendar.current.date(byAdding: .year, value: 3, to: from)!
        let old = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [calendar]))
        for event in old { try? store.remove(event, span: .thisEvent, commit: false) }

        for item in agenda where item.end >= from {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.location = item.location
            event.notes = item.notes
            event.startDate = item.start
            event.endDate = item.end
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    private static func existingCalendar() -> EKCalendar? {
        UserDefaults.standard.string(forKey: calendarIDKey).flatMap { store.calendar(withIdentifier: $0) }
    }

    private static func makeCalendar() -> EKCalendar? {
        // Prefer the account of the user's default calendar. Some accounts (Google, many Exchange servers)
        // don't let apps add calendars, so fall back to iCloud, then On My iPhone, then anything else.
        let preferred = store.defaultCalendarForNewEvents?.source
        let others = [EKSourceType.calDAV, .local, .exchange].flatMap { type in
            store.sources.filter { $0.sourceType == type && $0 !== preferred }
        }
        for source in [preferred].compactMap({ $0 }) + others {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = "Volunteering"
            calendar.cgColor = CGColor(red: 0x12 / 255, green: 0x3B / 255, blue: 0x2A / 255, alpha: 1)
            calendar.source = source
            guard (try? store.saveCalendar(calendar, commit: true)) != nil else { continue }
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIDKey)
            return calendar
        }
        return nil
    }
}
