import Foundation
import UserNotifications

/// Reminders for what's on the volunteer's calendar: 7 PM the evening before and an hour before,
/// plus a "log your hours" nudge when a signed-up shift ends. Scheduled on the phone, so no push server is needed.
@MainActor
enum Reminders {
    private static let center = UNUserNotificationCenter.current()
    private static let enabledKey = "remindersEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks for notification permission. Returns false if the user said no.
    static func enable() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        return granted
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        center.removeAllPendingNotificationRequests()
    }

    // ponytail: iOS keeps at most 64 pending notifications, so only the next 20 items get reminders (3 each).
    // Rescheduled on every refresh, so later items are picked up as earlier ones pass.
    static func sync(_ agenda: [AgendaItem]) {
        guard isEnabled else { return }
        center.removeAllPendingNotificationRequests()
        let calendar = Calendar.current
        for item in agenda.filter({ $0.end > Date() }).prefix(20) {
            let starts = "Starts at \(item.start.formatted(date: .omitted, time: .shortened))" +
                (item.location.isEmpty ? "." : " at \(item.location).")
            if let dayBefore = calendar.date(byAdding: .day, value: -1, to: item.start),
               let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: dayBefore) {
                schedule("\(item.id)-evening", at: evening, title: "Tomorrow: \(item.title)", body: starts)
            }
            schedule("\(item.id)-hour", at: item.start.addingTimeInterval(-3600), title: "In 1 hour: \(item.title)", body: starts)
            if item.kind.isSignup {
                schedule("\(item.id)-ended", at: item.end, title: "How did \(item.title) go?",
                         body: "Log your hours in Letterman while it's fresh.")
            }
        }
    }

    private static func schedule(_ id: String, at date: Date, title: String, body: String) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
    }
}
