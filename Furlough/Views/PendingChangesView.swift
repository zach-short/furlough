import SwiftUI

struct PendingChangesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.state.pending.sorted { $0.effectiveAt < $1.effectiveAt }) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        if let id = change.targetID, let target = model.state.config.target(id: id) {
                            HStack(spacing: 6) {
                                TokenLabel(kind: target.kind)
                                if !target.nickname.isEmpty {
                                    Text("· \(target.nickname)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(describe(change))
                            .font(.subheadline)
                        Text("Takes effect \(change.effectiveAt.formatted(date: .abbreviated, time: .shortened)) · \(change.effectiveAt, style: .relative) from now")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .swipeActions {
                        Button("Cancel change", systemImage: "xmark", role: .destructive) {
                            model.cancelPending(id: change.id)
                        }
                    }
                }
            }
            .overlay {
                if model.state.pending.isEmpty {
                    ContentUnavailableView("Nothing pending", systemImage: "checkmark.circle", description: Text("Loosening edits wait here until they take effect."))
                }
            }
            .navigationTitle("Pending changes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func describe(_ change: PendingChange) -> String {
        switch change.kind {
        case .setRule(_, let rule): "New rule: \(TimeFormat.rule(rule))"
        case .removeTarget: "Remove from Furlough"
        case .setDelay(let hours): "Loosening delay becomes \(TimeFormat.delay(hours: hours))"
        }
    }
}
