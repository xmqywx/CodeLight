import UIKit

/// Lightweight wrapper around UIKit haptic generators. Used throughout the app
/// to add tactile feedback for taps, confirmations, and state changes.
///
/// Generators are prepared lazily the first time they're used and cached so
/// repeat calls don't suffer the ~50ms warm-up delay. Call `prepareAll()` at
/// app launch if you want the first haptic of the session to fire instantly.
enum Haptics {

    // MARK: - Impact

    /// Soft, barely-perceptible tap — use for list row selections, nav pushes,
    /// and other "passive" interactions. Avoid spamming.
    static func light() {
        impactLight.impactOccurred()
    }

    /// Medium tap — the default "something happened" feel. Use for button
    /// presses, attachment picker triggers, picker value changes.
    static func medium() {
        impactMedium.impactOccurred()
    }

    /// Sharp tap — for deliberate commit actions (send, pair, launch).
    /// Saves the "heavy" weight for genuinely heavy actions.
    static func rigid() {
        impactRigid.impactOccurred()
    }

    // MARK: - Notification

    /// Double-tap + rise — successful completion of a meaningful action
    /// (pair success, launch success, reconnect success).
    static func success() {
        notification.notificationOccurred(.success)
    }

    /// Three descending taps — non-blocking warning, e.g. before a destructive
    /// confirmation alert.
    static func warning() {
        notification.notificationOccurred(.warning)
    }

    /// Double tap + drop — operation failed.
    static func error() {
        notification.notificationOccurred(.error)
    }

    // MARK: - Selection

    /// Discrete click — for segmented control taps, picker rotation, tab changes.
    static func selection() {
        selectionGen.selectionChanged()
    }

    /// Call on app launch to warm up the haptic engines so the first haptic
    /// of the session isn't delayed.
    static func prepareAll() {
        impactLight.prepare()
        impactMedium.prepare()
        impactRigid.prepare()
        notification.prepare()
        selectionGen.prepare()
    }

    // MARK: - Cached generators

    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGen = UISelectionFeedbackGenerator()
}
