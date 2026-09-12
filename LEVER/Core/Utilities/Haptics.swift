import UIKit

/// Restrained haptic vocabulary — used only for moments that matter.
enum Haptics {
    static func scanSucceeded() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func savingConfirmed() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func actionCompleted() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func importantDeadline() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func failed() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
