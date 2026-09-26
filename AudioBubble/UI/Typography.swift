import Foundation

extension String {
    /// The copy with the last two words of each sentence joined by a no-break space, so a
    /// wrapped line never ends a sentence with one word on its own (a widow).
    ///
    /// Applies at each `.`, `!`, `?` or `…` that ends a sentence, and at the end of text without
    /// one ("Connect headphones to join a bubble"). A one-word sentence is left alone rather than
    /// glued to the sentence before it.
    var withoutWidows: String {
        let terminators: Set<Character> = [".", "!", "?", "…"]
        var characters = Array(self)
        var lastSpace: Int?
        for i in characters.indices {
            let c = characters[i]
            if c == " " {
                // A space right after a sentence ends starts the next sentence; never join across it.
                lastSpace = i > 0 && terminators.contains(characters[i - 1]) ? nil : i
            } else if terminators.contains(c), i + 1 == characters.count || characters[i + 1] == " " {
                if let space = lastSpace { characters[space] = "\u{00A0}" }
                lastSpace = nil
            }
        }
        if let space = lastSpace { characters[space] = "\u{00A0}" }
        return String(characters)
    }
}
