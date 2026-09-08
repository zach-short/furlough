import Combine
import AppKit
import SwiftUI

/// The menu bar item: an hourglass and, while something is open, the countdown.
struct MenuBarLabel: View {
    @Environment(MacModel.self) private var model
    @State private var now = Date.now
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let summary = Policy.summary(state: model.state, now: now)
        HStack(spacing: 4) {
            Image(systemName: summary.openUntil != nil || !summary.allDayNames.isEmpty ? "hourglass.bottomhalf.filled" : "hourglass")
            if let until = summary.openUntil {
                Text(TimeFormat.countdown(from: now, to: until)).monospacedDigit()
            }
        }
        .onReceive(clock) { now = $0 }
    }
}

struct MenuBarContent: View {
    @Environment(MacModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let now = Date.now
        let targets = model.state.config.targets
        if targets.isEmpty {
            Text("Nothing in Furlough yet")
        }
        ForEach(targets) { target in
            let status = Policy.status(of: target, config: model.state.config, runtime: model.state.runtime, now: now)
            Text("\(target.displayName): \(TimeFormat.status(status))")
        }
        Divider()
        Button("Open Furlough") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")
    }
}
