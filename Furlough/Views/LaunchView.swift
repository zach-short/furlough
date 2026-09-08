import SwiftUI

/// The first moment of a launch for someone who has already set Furlough up. After a cold
/// start FamilyControls says "not determined" until it has asked the system, which used to
/// flash onboarding before Home. Instead the root holds this screen for `Launch.hold` and then
/// dissolves it into the app. It draws no wall of its own: the root's wall stays put
/// underneath, so the dissolve moves only the hourglass and the name.
struct LaunchView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 30) {
            LivingHourglass(state: .launching)
                .compositingGroup()
                .frame(width: 106, height: 140)
                .shadow(color: Ember.amber.opacity(0.45), radius: 24)
            Eyebrow(text: "Furlough", color: Ember.amber)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: Launch.rise)) { appeared = true }
        }
    }
}

/// The launch screen's timing, in one place.
enum Launch {
    /// The wall, the hourglass and the name fade up from the flat launch colour.
    static let rise: TimeInterval = 0.45
    /// How long the screen stays before it may dissolve, whatever iOS has said by then.
    static let hold: Duration = .seconds(1)
    /// How much longer it waits, at most, for FamilyControls to give a definite answer.
    static let patience: Duration = .seconds(2)
    /// The dissolve into Home, or into onboarding when access was taken away.
    static let dissolve: TimeInterval = 0.55
}

extension HourglassState {
    /// Sand running under a quiet amber glow: nothing about any target, just the app waking up.
    static let launching = HourglassState(
        sandLevel: 0.62, moundLevel: 0.38, isRunning: true, glow: Ember.amber, glowStrength: 0.6, pulse: .slow
    )
}
