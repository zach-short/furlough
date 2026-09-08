import AppIntents
import Foundation

/// The one action both Furloughs share: what is open, said in a sentence.
///
/// Read-only, and that is the whole reason it can sit a tap away under the app's name in
/// Spotlight. Furlough's rule is that tightening is instant and loosening waits, so anything
/// reachable from outside the app has to be one or the other; this is neither, because it
/// changes nothing at all. Asking is always allowed.
struct WhatsOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Open"
    static let description = IntentDescription(
        "Says what Furlough is letting through right now, and when the next thing opens.",
        categoryName: "Status",
        searchKeywords: ["open", "blocked", "status", "anchor", "time left"]
    )
    /// Answering by opening the app would defeat the point: the answer is meant to arrive
    /// without leaving whatever you were doing to ask it.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        // Furlough's own time, not the device's — the same clock the widget and the shield
        // read, so a phone whose clock has been moved forward gets the honest answer.
        let state = SharedStore.load()
        let now = state.clock().now
        let sentence = StatusSpeech.sentence(
            Policy.summary(state: state, now: now),
            hasTargets: !state.config.targets.isEmpty,
            now: now
        )
        return .result(value: sentence, dialog: "\(sentence)")
    }
}
