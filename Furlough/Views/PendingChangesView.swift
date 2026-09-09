import SwiftUI

struct PendingChangesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let pending = model.state.pending.sorted { $0.effectiveAt < $1.effectiveAt }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let clock = model.state.clock()
                    if !clock.isTrusted {
                        ClockBanner(drift: clock.drift)
                    }
                    if pending.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(Ember.moss)
                            Text("Nothing pending")
                                .emberDisplay(24)
                                .foregroundStyle(Ember.cream)
                            Text("Loosening edits wait here until they take effect.")
                                .emberBody(13)
                                .foregroundStyle(Ember.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                    ForEach(pending) { change in
                        PendingCard(
                            change: change,
                            target: change.targetID.flatMap { model.state.config.target(id: $0) },
                            delta: PendingText.delta(for: change, in: model.state.config)
                        ) {
                            withAnimation(.snappy) { model.cancelPending(id: change.id) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Pending")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Ember.cream)
                }
            }
        }
        .presentationBackground(Ember.ground)
    }
}

struct PendingCard: View {
    let change: PendingChange
    let target: Target?
    let delta: PendingText.Delta
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let target {
                    TokenTile(kind: target.kind, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TokenName(kind: target.kind)
                            if !target.nickname.isEmpty {
                                Text(target.nickname)
                                    .emberBody(11.5)
                                    .foregroundStyle(Ember.muted)
                            }
                        }
                        PendingDeltaView(delta: delta)
                    }
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Ember.pending)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(PendingText.subject(of: change.kind) ?? "Loosening delay")
                            .emberDisplaySmall(13.5)
                            .foregroundStyle(Ember.cream)
                        PendingDeltaView(delta: delta)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Text("Takes effect \(change.effectiveAt.formatted(date: .abbreviated, time: .shortened)) · \(change.effectiveAt, style: .relative) from now")
                .emberBody(11, .semibold)
                .foregroundStyle(Ember.pending)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
            CardDivider()
            GhostButton(title: "Cancel change", action: onCancel)
        }
        .emberCard()
    }
}
