import Foundation
import EventKit

/// Puts a money deadline on the user's calendar. Write-only access — LEVER never reads calendars.
struct CalendarExporter: Sendable {
    func addDeadline(title: String, notes: String, date: Date) async -> Bool {
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return false }
        } catch {
            return false
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: date)
        event.endDate = event.startDate
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -24 * 60 * 60))
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }
}
