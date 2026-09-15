import AppIntents
import Foundation

/// What is open, said in a sentence. Read-only, which is why it can skip Furlough's
/// tighten-instant/loosen-waits rule entirely — asking is always allowed.
struct WhatsOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Open"
    static let description = IntentDescription(
        "Says what Furlough is letting through right now, and when the next thing opens.",
        categoryName: "Status",
        searchKeywords: ["open", "blocked", "status", "anchor", "time left"]
    )
    /// Opening the app would defeat the point: the answer should arrive without leaving what
    /// you were doing.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        // Furlough's own clock (same as the widget/shield), not the device's raw time.
        let state = SharedStore.load()
        let now = state.clock().now
        let sentence = StatusSpeech.sentence(
            Policy.summary(state: state, now: now, zone: state.zone(now: now)),
            hasTargets: !state.config.targets.isEmpty,
            now: now
        )
        return .result(value: sentence, dialog: "\(sentence)")
    }
}
