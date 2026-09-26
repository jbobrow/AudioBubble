import SwiftUI
import UIKit

/// Choose a Memoji (or any emoji, sticker or Genmoji) for your bubble.
///
/// iOS has no API for reading someone's Memoji; the way in is the emoji keyboard. A text view
/// that supports adaptive image glyphs receives Memoji stickers as images, so this sheet opens a
/// small one, already on the emoji keyboard, and takes the first thing the user picks.
struct AvatarPicker: View {
    let name: String
    let hue: Double
    let onPick: (AvatarChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 36, height: 5).padding(.top, 8)
            Text("Choose your Memoji".withoutWidows)
                .font(.title3.weight(.semibold))
            Text("On the emoji keyboard, swipe right to your Memoji stickers, or pick any emoji.".withoutWidows)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            ZStack {
                BubbleAvatar(name: name, hue: hue, size: 84)
                    .opacity(0.35)
                EmojiInput(onPick: pick)
                    .frame(width: 84, height: 84)
            }
            if failed {
                Text("That one couldn't be used. Try another.".withoutWidows)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 14) {
                Button("Use my initial") { onPick(.initial); dismiss() }
                    .buttonStyle(.bordered)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background(Background())
    }

    private func pick(_ picked: EmojiInput.Picked) {
        switch picked {
        case let .emoji(emoji):
            onPick(.emoji(emoji))
            dismiss()
        case let .image(image):
            if let data = AvatarImage.prepare(image) {
                onPick(.image(data))
                dismiss()
            } else {
                failed = true
            }
        }
    }
}

/// A one-character text view that opens on the emoji keyboard and reports what was chosen.
private struct EmojiInput: UIViewRepresentable {
    enum Picked { case emoji(String), image(UIImage) }
    let onPick: (Picked) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIView(context: Context) -> EmojiTextView {
        let view = EmojiTextView()
        view.delegate = context.coordinator
        view.supportsAdaptiveImageGlyph = true   // Memoji, stickers and Genmoji arrive as images
        view.allowsEditingTextAttributes = true   // older sticker path: image attachments
        view.backgroundColor = .clear
        view.tintColor = .white
        view.font = .systemFont(ofSize: 44)
        view.textAlignment = .center
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        view.isScrollEnabled = false
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: EmojiTextView, context: Context) {}

    final class Coordinator: NSObject, UITextViewDelegate {
        let onPick: (Picked) -> Void
        init(onPick: @escaping (Picked) -> Void) { self.onPick = onPick }

        func textViewDidChange(_ textView: UITextView) {
            let text = textView.attributedText ?? NSAttributedString()
            guard text.length > 0, let picked = Self.firstPick(in: text) else {
                textView.text = ""
                return
            }
            textView.resignFirstResponder()
            onPick(picked)
        }

        static func firstPick(in text: NSAttributedString) -> Picked? {
            let range = NSRange(location: 0, length: text.length)
            var image: UIImage?
            text.enumerateAttribute(.adaptiveImageGlyph, in: range) { value, _, stop in
                if let glyph = value as? NSAdaptiveImageGlyph, let decoded = UIImage(data: glyph.imageContent) {
                    image = decoded
                    stop.pointee = true
                }
            }
            if image == nil {
                text.enumerateAttribute(.attachment, in: range) { value, _, stop in
                    guard let attachment = value as? NSTextAttachment else { return }
                    image = attachment.image
                        ?? attachment.contents.flatMap(UIImage.init(data:))
                        ?? attachment.fileWrapper?.regularFileContents.flatMap(UIImage.init(data:))
                    if image != nil { stop.pointee = true }
                }
            }
            if let image { return .image(image) }
            if let emoji = text.string.first(where: \.isEmoji) { return .emoji(String(emoji)) }
            return nil
        }
    }
}

/// Opens on the emoji keyboard when one is enabled.
final class EmojiTextView: UITextView {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

extension Character {
    /// A character drawn as an emoji (not a plain digit or symbol that merely *can* be one).
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && (unicodeScalars.count > 1 || first.value > 0x238C))
    }
}
