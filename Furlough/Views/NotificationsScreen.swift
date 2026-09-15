import SwiftUI

/// One switch per notification Furlough posts.
///
/// The lead line is the point of the screen: muting changes nothing about what is shielded, so
/// this is the rare setting here that applies at once and waits out no delay. Before it, the
/// only lever was iOS's own switch, which takes "Time's up" and the loosening warnings with it.
struct NotificationsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AnchorSettingScreen(title: "Notifications", lead: lead) {
            VStack(spacing: 0) {
                ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { CardDivider() }
                    row(kind)
                }
            }
            .emberCard()
            Footnote(text: "This iPhone's own answers. They are not part of your setup and never cross to another device — and nothing here is enforced, so none of it waits out the delay.")
                .padding(.top, 8)
        }
    }

    private var lead: String {
        let base = "Muting one of these blocks nothing and unblocks nothing, so it takes effect the moment you tap it."
        guard model.notificationsGranted == false else { return base }
        return "\(base) Notifications are off for Furlough, so none of them arrive until they are allowed."
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
