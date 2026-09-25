import SwiftUI

/// "Maya wants to bubble with you", with Join and Not now.
struct InviteBanner: View {
    @Environment(AppModel.self) private var model
    let invite: IncomingInvite

    var body: some View {
        let peer = model.peer(invite.from)
        HStack(spacing: 14) {
            BubbleAvatar(name: peer?.name ?? "?", hue: peer?.hue ?? 0.6, size: 44,
                         content: peer.map(model.avatar(of:)) ?? .initial)
            Text("\(peer?.name ?? "Someone") wants to bubble with you")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                Button("Join", action: model.acceptInvite)
                    .buttonStyle(.borderedProminent)
                Button("Not now", action: model.declineInvite)
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.top, 4)
    }
}
