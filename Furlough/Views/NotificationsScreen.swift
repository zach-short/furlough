import SwiftUI

/// One switch per notification Furlough posts.
struct NotificationsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AnchorSettingScreen(title: "Notifications") {
            VStack(spacing: 0) {
                ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { CardDivider() }
                    row(kind)
                }
            }
            .emberCard()
        }
    }

    private func row(_ kind: NotificationKind) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Text(kind.detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(
                kind.title,
                isOn: Binding(
                    get: { !model.mutedNotifications.contains(kind) },
                    set: { model.setNotification(kind, on: $0) }
                )
            )
            .labelsHidden()
            .tint(Ember.ember)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
