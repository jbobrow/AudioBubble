import SwiftUI

/// SwiftUI host for `BubbleFieldView`. SwiftUI only hands it data when people come and go (or
/// change); it does no work while bubbles move.
struct BubbleField: UIViewRepresentable {
    let bubbles: [BubbleModel]
    let onTap: (UInt64) -> Void

    func makeUIView(context: Context) -> BubbleFieldView {
        BubbleFieldView(frame: .zero)
    }

    func updateUIView(_ view: BubbleFieldView, context: Context) {
        view.onTap = onTap
        view.setBubbles(bubbles)
    }
}
