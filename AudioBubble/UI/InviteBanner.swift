import SwiftUI

/// "Maya wants to bubble with you", with Decline and Join.
struct InviteBanner: View {
    @Environment(AppModel.self) private var model
    let invite: IncomingInvite

    var body: some View {
        let peer = model.peer(invite.from)
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                BubbleAvatar(name: peer?.name ?? "?", hue: peer?.hue ?? 0.6, size: 48,
                             content: peer.map(model.avatar(of:)) ?? .initial)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(peer?.name ?? "Someone") wants to bubble with you".withoutWidows)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.headphonesConnected {
                        Label("Connect headphones to join".withoutWidows, systemImage: "airpods")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Join on the right (where a thumb lands) and wider than Decline.
            HStack(spacing: 10) {
                Button(role: .destructive, action: model.declineInvite) {
                    Text("Decline")
                        .font(.headline)
                        .foregroundStyle(.red)   // the banner's white text would otherwise win
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                Button(action: model.acceptInvite) {
                    Text("Join")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .layoutPriority(2)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.top, 4)
    }
}
