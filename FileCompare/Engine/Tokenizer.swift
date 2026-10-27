import Foundation

/// The lexical category of a ``TextToken``.
///
/// The categories exist to let the word-level diff reason about structure
/// (for example, to drop whitespace from comparison while keeping it in the
/// rendered output) rather than to be a general-purpose lexer.
enum TokenKind: Hashable, Sendable {
    /// A maximal run of whitespace characters.
    case whitespace
    /// A maximal run of letters, digits, underscores and combining marks.
    case word
    /// A single Han / CJK ideograph.
    case ideograph
    /// A single punctuation character, symbol, or emoji grapheme cluster.
    case punctuation
}

/// One unit of a tokenized line.
struct TextToken: Hashable, Sendable {
    var text: String
    var kind: TokenKind

    init(text: String, kind: TokenKind) {
        self.text = text
        self.kind = kind
    }

    var isWhitespace: Bool { kind == .whitespace }

    /// The key used when matching this token against tokens of the other side.
    ///
    /// Case folding has to happen here (instead of once per line) so that the
    /// word diff can keep the original characters in the runs it returns.
    func comparisonKey(ignoreCase: Bool) -> String {
        ignoreCase ? text.lowercased() : text
    }
}

/// Splits a single line into tokens for word-level comparison and highlighting.
///
/// Rules:
/// - A run of whitespace is one token.
/// - Each Han / CJK ideograph is its own token, so a Chinese phrase is
///   compared character by character.
/// - Consecutive letters, digits and underscores accumulate into one word
///   token (combining marks and join controls stay inside the word).
/// - Everything else — punctuation, symbols and emoji grapheme clusters —
///   becomes one token per `Character`.
///
/// Tokenizing is lossless: `tokenize(line).map(\.text).joined() == line`.
enum Tokenizer {
    /// Tokenizes `line` without changing any of its characters.
    static func tokenize(_ line: String) -> [TextToken] {
        var tokens: [TextToken] = []
        var wordBuffer = ""

        func flushWord() {
            guard !wordBuffer.isEmpty else { return }
            tokens.append(TextToken(text: wordBuffer, kind: .word))
            wordBuffer.removeAll(keepingCapacity: true)
        }

        for character in line {
            if character.isWhitespace {
                flushWord()
                appendWhitespace(character, to: &tokens)
            } else if isIdeograph(character) {
                flushWord()
                tokens.append(TextToken(text: String(character), kind: .ideograph))
            } else if isWordCharacter(character) {
                wordBuffer.append(character)
            } else {
                flushWord()
                tokens.append(TextToken(text: String(character), kind: .punctuation))
            }
        }

        flushWord()
        return tokens
    }

    /// Tokenizes `line` and returns only the token texts.
    static func tokenTexts(in line: String) -> [String] {
        tokenize(line).map(\.text)
    }

    // MARK: - Character classification

    private static func appendWhitespace(_ character: Character, to tokens: inout [TextToken]) {
        if var last = tokens.last, last.kind == .whitespace {
            last.text.append(character)
            tokens[tokens.count - 1] = last
        } else {
            tokens.append(TextToken(text: String(character), kind: .whitespace))
        }
    }

    private static func isIdeograph(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return scalar.properties.isIdeographic
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        guard !character.unicodeScalars.isEmpty else { return false }

        for scalar in character.unicodeScalars {
            // Emoji must not be folded into words. Keycap sequences such as
            // `1️⃣` start with an ASCII digit, so their emoji nature is carried
            // by the variation selector and the combining enclosing keycap
            // rather than by the base scalar.
            if isEmojiScalar(scalar) { return false }
            if scalar == "_" { continue }

            let properties = scalar.properties

            if properties.isAlphabetic || properties.numericType != nil { continue }

            switch properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark,
                 .modifierLetter, .decimalNumber, .letterNumber, .otherNumber:
                continue
            default:
                return false
            }
        }

        return true
    }

    /// Whether a scalar marks a grapheme as emoji for tokenization purposes.
    ///
    /// In addition to scalars with an emoji presentation this recognises the
    /// variation selector-16 and the combining enclosing keycap, which are the
    /// only hints that the ASCII digit in a keycap sequence like `1️⃣` is part
    /// of an emoji cluster. ZWJ, flag, and skin-tone clusters are already
    /// rejected by the general-category check, but detecting their scalars here
    /// keeps the rule in one place.
    private static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isEmojiPresentation { return true }

        switch scalar.value {
        case 0xFE0F, 0x20E3, // variation selector-16, combining enclosing keycap
             0x200D,        // zero width joiner
             0x1F3FB...0x1F3FF, // emoji skin tone modifiers
             0x1F1E6...0x1F1FF: // regional indicators (flags)
            return true
        default:
            return false
        }
    }
}
