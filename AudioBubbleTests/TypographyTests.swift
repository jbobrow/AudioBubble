import Testing
@testable import AudioBubble

struct TypographyTests {
    let nbsp = "\u{00A0}"

    @Test func joinsTheLastTwoWordsOfEachSentence() {
        #expect("Keep Wi-Fi on. No network needed.".withoutWidows == "Keep Wi-Fi\(nbsp)on. No network\(nbsp)needed.")
        #expect("That one couldn't be used. Try another.".withoutWidows == "That one couldn't be\(nbsp)used. Try\(nbsp)another.")
        #expect("Is it on? Yes it is!".withoutWidows == "Is it\(nbsp)on? Yes it\(nbsp)is!")
        #expect("Looking for people nearby…".withoutWidows == "Looking for people\(nbsp)nearby…")
    }

    @Test func handlesTextWithoutAFinalPeriod() {
        #expect("Connect headphones to join a bubble".withoutWidows == "Connect headphones to join a\(nbsp)bubble")
        #expect("Jonathan wants to bubble with you".withoutWidows == "Jonathan wants to bubble with\(nbsp)you")
    }

    @Test func leavesOneWordSentencesAndDecimalsAlone() {
        // A one-word sentence isn't glued to the sentence before it.
        #expect("Put them in. Done.".withoutWidows == "Put them\(nbsp)in. Done.")
        #expect("Hello".withoutWidows == "Hello")
        // A period inside a word (a version, a domain) isn't a sentence end.
        #expect("Version 2.5 is out".withoutWidows == "Version 2.5 is\(nbsp)out")
        #expect("".withoutWidows == "")
    }
}
