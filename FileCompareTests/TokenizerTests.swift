import Foundation
import Testing

@testable import FileCompare

struct TokenizerTests {
    @Test func whitespaceRunsAreSingleTokens() {
        let tokens = Tokenizer.tokenize("a \t  b")
        #expect(tokens.map(\.text) == ["a", " \t  ", "b"])
        #expect(tokens.map(\.kind) == [.word, .whitespace, .word])
    }

    @Test func wordsAccumulateLettersDigitsAndUnderscores() {
        #expect(Tokenizer.tokenTexts(in: "snake_case_42") == ["snake_case_42"])
        #expect(Tokenizer.tokenize("snake_case_42").first?.kind == .word)
        #expect(Tokenizer.tokenTexts(in: "SwiftUI macOS27") == ["SwiftUI", " ", "macOS27"])
    }

    @Test func hanIdeographsAreSingleTokens() {
        let line = "我们今天去公园散步"
        let tokens = Tokenizer.tokenize(line)

        #expect(tokens.count == 9)
        #expect(tokens.allSatisfy { $0.kind == .ideograph })
        #expect(tokens.map(\.text).joined() == line)
    }

    @Test func punctuationAndEmojiUseOneTokenPerCharacter() {
        let line = "Hi, 世界! 🎉👨‍👩‍👧"
        let tokens = Tokenizer.tokenize(line)

        #expect(tokens.map(\.text) == ["Hi", ",", " ", "世", "界", "!", " ", "🎉", "👨‍👩‍👧"])
        #expect(tokens.map(\.kind) == [
            .word, .punctuation, .whitespace,
            .ideograph, .ideograph, .punctuation,
            .whitespace, .punctuation, .punctuation,
        ])
    }

    @Test func tokenConcatenationPreservesInput() {
        let samples = [
            "The quick brown fox",
            "我们今天去公园散步",
            "Hi, 世界! 🎉",
            "e\u{301} café",
            "  leading and trailing  ",
            "a\tb  c",
            "",
            "👨‍👩‍👧‍👦 family",
            "snake_case_42 + SwiftUI",
        ]

        for line in samples {
            let joined = Tokenizer.tokenize(line).map(\.text).joined()
            #expect(joined == line)
        }
    }

    @Test func whitespaceCharactersArePreservedVerbatim() {
        // Includes a non-breaking space, which is whitespace but not a plain space.
        let line = "\t foo\u{00A0}bar "
        let tokens = Tokenizer.tokenize(line)

        #expect(tokens.map(\.text).joined() == line)
        #expect(tokens.contains { $0.kind == .whitespace })
    }

    @Test func keycapEmojiArePunctuationTokens() {
        let line = "1️⃣2️⃣"
        let tokens = Tokenizer.tokenize(line)

        #expect(tokens.count == 2)
        #expect(tokens.allSatisfy { $0.kind == .punctuation })
        #expect(tokens.map(\.text).joined() == line)

        // A keycap sequence must not merge with adjacent word characters.
        let mixed = Tokenizer.tokenize("a1️⃣b")
        #expect(mixed.map(\.text) == ["a", "1️⃣", "b"])
        #expect(mixed.map(\.kind) == [.word, .punctuation, .word])
    }

    @Test func emojiClustersStaySeparateFromWords() {
        #expect(Tokenizer.tokenTexts(in: "👨‍👩‍👧‍👦x") == ["👨‍👩‍👧‍👦", "x"])
        #expect(Tokenizer.tokenTexts(in: "🇨🇳🇺🇸") == ["🇨🇳", "🇺🇸"])
        #expect(Tokenizer.tokenTexts(in: "👍🏽ok") == ["👍🏽", "ok"])
        #expect(Tokenizer.tokenTexts(in: "snowman☃️!") == ["snowman", "☃️", "!"])

        for text in ["👨‍👩‍👧‍👦x", "🇨🇳🇺🇸", "👍🏽ok", "snowman☃️!"] {
            let tokens = Tokenizer.tokenize(text)
            #expect(tokens.map(\.text).joined() == text)
            #expect(tokens.allSatisfy { token in
                token.kind == .word || token.kind == .punctuation || token.kind == .whitespace
            })
        }
    }

    @Test func emojiTokenizationIsLossless() {
        let samples = [
            "1️⃣2️⃣",
            "a1️⃣b",
            "👨‍👩‍👧‍👦 family",
            "🇨🇳 🇺🇸 flags",
            "👍🏽👎🏻",
            "🏳️‍🌈 rainbow",
            "keycap 3️⃣ and 4️⃣",
        ]

        for line in samples {
            let joined = Tokenizer.tokenize(line).map(\.text).joined()
            #expect(joined == line)
        }
    }

    @Test func plainDigitsRemainWordCharacters() {
        // ASCII digits are Emoji-capable (for keycaps) but must stay in words
        // unless they are actually followed by emoji selectors.
        #expect(Tokenizer.tokenTexts(in: "macOS27") == ["macOS27"])
        #expect(Tokenizer.tokenTexts(in: "108") == ["108"])
        #expect(Tokenizer.tokenize("108").first?.kind == .word)
    }
}
