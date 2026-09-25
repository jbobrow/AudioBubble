import SwiftUI

/// "Maya wants to bubble with you", with Join and Not now.
struct InviteBanner: View {
    @Environment(AppModel.self) private var model
    let invite: IncomingInvite

    var body: some View {
        let peer = model.peer(invite.from)
        HStack(spacing: 14) {
            Circle()
                .fill(Color.bubble(peer?.hue ?? 0.6).gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Text((peer?.name.prefix(1) ?? "?").uppercased())
                        .font(.headline)
                        .foregroundStyle(.black.opacity(0.6))
                }
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
