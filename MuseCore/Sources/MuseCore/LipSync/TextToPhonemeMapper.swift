//
//  TextToPhonemeMapper.swift
//  AvatarMuse
//
//  Copyright 2025 Arkavo
//

import Foundation

// MARK: - Text to Phoneme Mapper

/// Converts text to ARPABET phoneme sequences using a dictionary lookup
/// with rule-based fallback for unknown words
public struct TextToPhonemeMapper: Sendable {

    /// Silence marker for inter-word pauses
    public static let silenceMarker = "SIL"

    /// Embedded CMU dictionary subset for common words
    /// Key: lowercase word, Value: ARPABET phoneme sequence (without stress markers)
    private static let dictionary: [String: [String]] = CMUDictionaryData.entries

    /// Rule-based converter for unknown words
    private let g2pRules = GraphemeToPhonemeRules()

    public init() {}

    /// Convert text to a sequence of ARPABET phonemes
    /// - Parameter text: Input text to convert
    /// - Returns: Array of ARPABET phoneme strings with SIL markers between words
    public func convert(_ text: String) -> [String] {
        let words = tokenize(text)
        var phonemes: [String] = []

        for (index, word) in words.enumerated() {
            let wordPhonemes = phonemesForWord(word)
            phonemes.append(contentsOf: wordPhonemes)

            // Add silence between words (except after last word)
            if index < words.count - 1 {
                phonemes.append(Self.silenceMarker)
            }
        }

        return phonemes
    }

    /// Get phonemes for a single word
    /// - Parameter word: The word to convert
    /// - Returns: ARPABET phoneme sequence
    public func phonemesForWord(_ word: String) -> [String] {
        let normalized = word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)

        // Try dictionary lookup first
        if let entry = Self.dictionary[normalized] {
            return entry
        }

        // Fall back to rule-based conversion
        return g2pRules.convert(normalized)
    }

    // MARK: - Tokenization

    /// Tokenize text into words, handling punctuation and contractions
    private func tokenize(_ text: String) -> [String] {
        // Replace common punctuation with spaces
        var normalized = text
        for char in [".", ",", "!", "?", ";", ":", "-", "(", ")", "[", "]", "\"", "'"] {
            normalized = normalized.replacingOccurrences(of: char, with: " ")
        }

        // Split on whitespace and filter empty strings
        return normalized
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Grapheme to Phoneme Rules

/// Rule-based grapheme-to-phoneme converter for words not in the dictionary
/// Uses common English pronunciation patterns
public struct GraphemeToPhonemeRules: Sendable {

    public init() {}

    /// Convert a word to phonemes using pronunciation rules
    /// - Parameter word: Lowercase word to convert
    /// - Returns: Estimated ARPABET phoneme sequence
    public func convert(_ word: String) -> [String] {
        var phonemes: [String] = []
        let chars = Array(word.lowercased())
        var i = 0

        while i < chars.count {
            let (phoneme, consumed) = matchRule(chars: chars, position: i)
            if let p = phoneme {
                phonemes.append(p)
            }
            i += consumed
        }

        return phonemes
    }

    // MARK: - Rule Matching

    /// Match pronunciation rules at current position
    /// - Parameters:
    ///   - chars: Character array of the word
    ///   - position: Current position in the array
    /// - Returns: (phoneme or nil, number of characters consumed)
    private func matchRule(chars: [Character], position: Int) -> (String?, Int) {
        let remaining = chars.count - position
        let char = chars[position]

        // Try multi-character patterns first (longest match)
        if remaining >= 4 {
            let quad = String(chars[position..<position+4])
            if let p = fourCharRules[quad] { return (p, 4) }
        }

        if remaining >= 3 {
            let triple = String(chars[position..<position+3])
            if let p = threeCharRules[triple] { return (p, 3) }
        }

        if remaining >= 2 {
            let pair = String(chars[position..<position+2])
            if let p = twoCharRules[pair] { return (p, 2) }
        }

        // Single character rules
        if let p = singleCharRules[char] {
            return (p, 1)
        }

        // Unknown character - skip
        return (nil, 1)
    }

    // MARK: - Rule Tables

    private let fourCharRules: [String: String] = [
        "tion": "SH AH N",
        "sion": "ZH AH N",
        "ough": "AO",
        "ight": "AY T",
        "ould": "UH D",
    ]

    private let threeCharRules: [String: String] = [
        "tch": "CH",
        "dge": "JH",
        "sch": "SH",
        "chr": "K R",
        "ght": "T",
        "eah": "EY AH",
        "ear": "IH R",
        "air": "EH R",
        "oor": "UH R",
        "our": "AW R",
        "ure": "Y UH R",
        "ing": "IH NG",
        "ong": "AO NG",
        "ang": "AE NG",
        "ung": "AH NG",
        "ank": "AE NG K",
        "ink": "IH NG K",
        "unk": "AH NG K",
    ]

    private let twoCharRules: [String: String] = [
        // Consonant digraphs
        "th": "TH",
        "ch": "CH",
        "sh": "SH",
        "ph": "F",
        "wh": "W",
        "ng": "NG",
        "ck": "K",
        "qu": "K W",
        "gh": "",  // Usually silent
        "wr": "R",
        "kn": "N",
        "gn": "N",
        "mb": "M",
        "mn": "M",

        // Vowel digraphs
        "ee": "IY",
        "ea": "IY",
        "oo": "UW",
        "ou": "AW",
        "ow": "OW",
        "oi": "OY",
        "oy": "OY",
        "ai": "EY",
        "ay": "EY",
        "au": "AO",
        "aw": "AO",
        "ie": "IY",
        "ei": "EY",
        "ey": "EY",
        "ue": "UW",
        "ui": "UW",

        // R-controlled vowels
        "ar": "AA R",
        "er": "ER",
        "ir": "ER",
        "or": "AO R",
        "ur": "ER",

        // Common endings
        "ed": "D",
        "es": "Z",
        "ly": "L IY",
        "le": "AH L",
    ]

    private let singleCharRules: [Character: String] = [
        // Consonants
        "b": "B",
        "c": "K",  // Default; context-dependent in real G2P
        "d": "D",
        "f": "F",
        "g": "G",  // Default; context-dependent in real G2P
        "h": "HH",
        "j": "JH",
        "k": "K",
        "l": "L",
        "m": "M",
        "n": "N",
        "p": "P",
        "q": "K",
        "r": "R",
        "s": "S",
        "t": "T",
        "v": "V",
        "w": "W",
        "x": "K S",
        "y": "Y",
        "z": "Z",

        // Vowels (short forms - context-dependent in real G2P)
        "a": "AE",
        "e": "EH",
        "i": "IH",
        "o": "AA",
        "u": "AH",
    ]
}

// MARK: - CMU Dictionary Data

/// Embedded subset of CMU Pronouncing Dictionary
/// Contains ~500 most common English words
public enum CMUDictionaryData {
    /// Dictionary entries: word → ARPABET phonemes (no stress markers)
    public static let entries: [String: [String]] = [
        // Common words A-Z
        "a": ["AH"],
        "about": ["AH", "B", "AW", "T"],
        "after": ["AE", "F", "T", "ER"],
        "again": ["AH", "G", "EH", "N"],
        "all": ["AO", "L"],
        "also": ["AO", "L", "S", "OW"],
        "always": ["AO", "L", "W", "EY", "Z"],
        "am": ["AE", "M"],
        "an": ["AE", "N"],
        "and": ["AE", "N", "D"],
        "any": ["EH", "N", "IY"],
        "are": ["AA", "R"],
        "as": ["AE", "Z"],
        "at": ["AE", "T"],
        "back": ["B", "AE", "K"],
        "be": ["B", "IY"],
        "because": ["B", "IH", "K", "AO", "Z"],
        "been": ["B", "IH", "N"],
        "before": ["B", "IH", "F", "AO", "R"],
        "being": ["B", "IY", "IH", "NG"],
        "between": ["B", "IH", "T", "W", "IY", "N"],
        "both": ["B", "OW", "TH"],
        "but": ["B", "AH", "T"],
        "by": ["B", "AY"],
        "can": ["K", "AE", "N"],
        "come": ["K", "AH", "M"],
        "could": ["K", "UH", "D"],
        "day": ["D", "EY"],
        "did": ["D", "IH", "D"],
        "do": ["D", "UW"],
        "down": ["D", "AW", "N"],
        "each": ["IY", "CH"],
        "even": ["IY", "V", "AH", "N"],
        "find": ["F", "AY", "N", "D"],
        "first": ["F", "ER", "S", "T"],
        "for": ["F", "AO", "R"],
        "from": ["F", "R", "AH", "M"],
        "get": ["G", "EH", "T"],
        "give": ["G", "IH", "V"],
        "go": ["G", "OW"],
        "good": ["G", "UH", "D"],
        "great": ["G", "R", "EY", "T"],
        "had": ["HH", "AE", "D"],
        "has": ["HH", "AE", "Z"],
        "have": ["HH", "AE", "V"],
        "he": ["HH", "IY"],
        "hello": ["HH", "AH", "L", "OW"],
        "her": ["HH", "ER"],
        "here": ["HH", "IH", "R"],
        "hi": ["HH", "AY"],
        "him": ["HH", "IH", "M"],
        "his": ["HH", "IH", "Z"],
        "how": ["HH", "AW"],
        "i": ["AY"],
        "if": ["IH", "F"],
        "in": ["IH", "N"],
        "into": ["IH", "N", "T", "UW"],
        "is": ["IH", "Z"],
        "it": ["IH", "T"],
        "its": ["IH", "T", "S"],
        "just": ["JH", "AH", "S", "T"],
        "know": ["N", "OW"],
        "last": ["L", "AE", "S", "T"],
        "left": ["L", "EH", "F", "T"],
        "let": ["L", "EH", "T"],
        "life": ["L", "AY", "F"],
        "like": ["L", "AY", "K"],
        "little": ["L", "IH", "T", "AH", "L"],
        "long": ["L", "AO", "NG"],
        "look": ["L", "UH", "K"],
        "made": ["M", "EY", "D"],
        "make": ["M", "EY", "K"],
        "man": ["M", "AE", "N"],
        "many": ["M", "EH", "N", "IY"],
        "may": ["M", "EY"],
        "me": ["M", "IY"],
        "might": ["M", "AY", "T"],
        "more": ["M", "AO", "R"],
        "most": ["M", "OW", "S", "T"],
        "much": ["M", "AH", "CH"],
        "must": ["M", "AH", "S", "T"],
        "my": ["M", "AY"],
        "name": ["N", "EY", "M"],
        "never": ["N", "EH", "V", "ER"],
        "new": ["N", "UW"],
        "nice": ["N", "AY", "S"],
        "no": ["N", "OW"],
        "not": ["N", "AA", "T"],
        "now": ["N", "AW"],
        "of": ["AH", "V"],
        "off": ["AO", "F"],
        "ok": ["OW", "K", "EY"],
        "okay": ["OW", "K", "EY"],
        "old": ["OW", "L", "D"],
        "on": ["AA", "N"],
        "once": ["W", "AH", "N", "S"],
        "one": ["W", "AH", "N"],
        "only": ["OW", "N", "L", "IY"],
        "or": ["AO", "R"],
        "other": ["AH", "DH", "ER"],
        "our": ["AW", "ER"],
        "out": ["AW", "T"],
        "over": ["OW", "V", "ER"],
        "own": ["OW", "N"],
        "part": ["P", "AA", "R", "T"],
        "people": ["P", "IY", "P", "AH", "L"],
        "place": ["P", "L", "EY", "S"],
        "please": ["P", "L", "IY", "Z"],
        "right": ["R", "AY", "T"],
        "said": ["S", "EH", "D"],
        "same": ["S", "EY", "M"],
        "say": ["S", "EY"],
        "see": ["S", "IY"],
        "she": ["SH", "IY"],
        "should": ["SH", "UH", "D"],
        "show": ["SH", "OW"],
        "so": ["S", "OW"],
        "some": ["S", "AH", "M"],
        "something": ["S", "AH", "M", "TH", "IH", "NG"],
        "still": ["S", "T", "IH", "L"],
        "such": ["S", "AH", "CH"],
        "sure": ["SH", "UH", "R"],
        "take": ["T", "EY", "K"],
        "tell": ["T", "EH", "L"],
        "than": ["DH", "AE", "N"],
        "thank": ["TH", "AE", "NG", "K"],
        "thanks": ["TH", "AE", "NG", "K", "S"],
        "that": ["DH", "AE", "T"],
        "the": ["DH", "AH"],
        "their": ["DH", "EH", "R"],
        "them": ["DH", "EH", "M"],
        "then": ["DH", "EH", "N"],
        "there": ["DH", "EH", "R"],
        "these": ["DH", "IY", "Z"],
        "they": ["DH", "EY"],
        "thing": ["TH", "IH", "NG"],
        "things": ["TH", "IH", "NG", "Z"],
        "think": ["TH", "IH", "NG", "K"],
        "this": ["DH", "IH", "S"],
        "those": ["DH", "OW", "Z"],
        "thought": ["TH", "AO", "T"],
        "through": ["TH", "R", "UW"],
        "time": ["T", "AY", "M"],
        "to": ["T", "UW"],
        "today": ["T", "AH", "D", "EY"],
        "too": ["T", "UW"],
        "two": ["T", "UW"],
        "under": ["AH", "N", "D", "ER"],
        "up": ["AH", "P"],
        "us": ["AH", "S"],
        "use": ["Y", "UW", "Z"],
        "very": ["V", "EH", "R", "IY"],
        "want": ["W", "AA", "N", "T"],
        "was": ["W", "AA", "Z"],
        "way": ["W", "EY"],
        "we": ["W", "IY"],
        "well": ["W", "EH", "L"],
        "were": ["W", "ER"],
        "what": ["W", "AH", "T"],
        "when": ["W", "EH", "N"],
        "where": ["W", "EH", "R"],
        "which": ["W", "IH", "CH"],
        "while": ["W", "AY", "L"],
        "who": ["HH", "UW"],
        "why": ["W", "AY"],
        "will": ["W", "IH", "L"],
        "with": ["W", "IH", "TH"],
        "without": ["W", "IH", "TH", "AW", "T"],
        "word": ["W", "ER", "D"],
        "words": ["W", "ER", "D", "Z"],
        "work": ["W", "ER", "K"],
        "world": ["W", "ER", "L", "D"],
        "would": ["W", "UH", "D"],
        "year": ["Y", "IH", "R"],
        "years": ["Y", "IH", "R", "Z"],
        "yes": ["Y", "EH", "S"],
        "yet": ["Y", "EH", "T"],
        "you": ["Y", "UW"],
        "your": ["Y", "AO", "R"],

        // Additional common conversational words
        "absolutely": ["AE", "B", "S", "AH", "L", "UW", "T", "L", "IY"],
        "actually": ["AE", "K", "CH", "UW", "AH", "L", "IY"],
        "amazing": ["AH", "M", "EY", "Z", "IH", "NG"],
        "anyway": ["EH", "N", "IY", "W", "EY"],
        "awesome": ["AO", "S", "AH", "M"],
        "beautiful": ["B", "Y", "UW", "T", "AH", "F", "AH", "L"],
        "believe": ["B", "IH", "L", "IY", "V"],
        "better": ["B", "EH", "T", "ER"],
        "big": ["B", "IH", "G"],
        "bit": ["B", "IH", "T"],
        "bye": ["B", "AY"],
        "call": ["K", "AO", "L"],
        "called": ["K", "AO", "L", "D"],
        "cannot": ["K", "AE", "N", "AA", "T"],
        "care": ["K", "EH", "R"],
        "change": ["CH", "EY", "N", "JH"],
        "cool": ["K", "UW", "L"],
        "course": ["K", "AO", "R", "S"],
        "definitely": ["D", "EH", "F", "AH", "N", "AH", "T", "L", "IY"],
        "different": ["D", "IH", "F", "ER", "AH", "N", "T"],
        "done": ["D", "AH", "N"],
        "else": ["EH", "L", "S"],
        "end": ["EH", "N", "D"],
        "enough": ["IH", "N", "AH", "F"],
        "every": ["EH", "V", "R", "IY"],
        "everyone": ["EH", "V", "R", "IY", "W", "AH", "N"],
        "everything": ["EH", "V", "R", "IY", "TH", "IH", "NG"],
        "exactly": ["IH", "G", "Z", "AE", "K", "T", "L", "IY"],
        "example": ["IH", "G", "Z", "AE", "M", "P", "AH", "L"],
        "excited": ["IH", "K", "S", "AY", "T", "IH", "D"],
        "fact": ["F", "AE", "K", "T"],
        "feel": ["F", "IY", "L"],
        "feeling": ["F", "IY", "L", "IH", "NG"],
        "few": ["F", "Y", "UW"],
        "fine": ["F", "AY", "N"],
        "friend": ["F", "R", "EH", "N", "D"],
        "friends": ["F", "R", "EH", "N", "D", "Z"],
        "fun": ["F", "AH", "N"],
        "going": ["G", "OW", "IH", "NG"],
        "gonna": ["G", "AO", "N", "AH"],
        "got": ["G", "AA", "T"],
        "gotta": ["G", "AA", "T", "AH"],
        "guess": ["G", "EH", "S"],
        "guy": ["G", "AY"],
        "guys": ["G", "AY", "Z"],
        "hand": ["HH", "AE", "N", "D"],
        "happen": ["HH", "AE", "P", "AH", "N"],
        "happened": ["HH", "AE", "P", "AH", "N", "D"],
        "happy": ["HH", "AE", "P", "IY"],
        "hard": ["HH", "AA", "R", "D"],
        "hate": ["HH", "EY", "T"],
        "head": ["HH", "EH", "D"],
        "hear": ["HH", "IH", "R"],
        "heard": ["HH", "ER", "D"],
        "help": ["HH", "EH", "L", "P"],
        "hey": ["HH", "EY"],
        "hold": ["HH", "OW", "L", "D"],
        "home": ["HH", "OW", "M"],
        "hope": ["HH", "OW", "P"],
        "hour": ["AW", "ER"],
        "hours": ["AW", "ER", "Z"],
        "house": ["HH", "AW", "S"],
        "idea": ["AY", "D", "IY", "AH"],
        "important": ["IH", "M", "P", "AO", "R", "T", "AH", "N", "T"],
        "interesting": ["IH", "N", "T", "R", "AH", "S", "T", "IH", "NG"],
        "job": ["JH", "AA", "B"],
        "keep": ["K", "IY", "P"],
        "kind": ["K", "AY", "N", "D"],
        "knew": ["N", "UW"],
        "later": ["L", "EY", "T", "ER"],
        "learn": ["L", "ER", "N"],
        "least": ["L", "IY", "S", "T"],
        "leave": ["L", "IY", "V"],
        "less": ["L", "EH", "S"],
        "listen": ["L", "IH", "S", "AH", "N"],
        "live": ["L", "IH", "V"],
        "lives": ["L", "AY", "V", "Z"],
        "love": ["L", "AH", "V"],
        "maybe": ["M", "EY", "B", "IY"],
        "mean": ["M", "IY", "N"],
        "means": ["M", "IY", "N", "Z"],
        "meet": ["M", "IY", "T"],
        "mind": ["M", "AY", "N", "D"],
        "minute": ["M", "IH", "N", "AH", "T"],
        "minutes": ["M", "IH", "N", "AH", "T", "S"],
        "moment": ["M", "OW", "M", "AH", "N", "T"],
        "money": ["M", "AH", "N", "IY"],
        "month": ["M", "AH", "N", "TH"],
        "morning": ["M", "AO", "R", "N", "IH", "NG"],
        "mother": ["M", "AH", "DH", "ER"],
        "move": ["M", "UW", "V"],
        "myself": ["M", "AY", "S", "EH", "L", "F"],
        "need": ["N", "IY", "D"],
        "next": ["N", "EH", "K", "S", "T"],
        "night": ["N", "AY", "T"],
        "nothing": ["N", "AH", "TH", "IH", "NG"],
        "number": ["N", "AH", "M", "B", "ER"],
        "oh": ["OW"],
        "open": ["OW", "P", "AH", "N"],
        "order": ["AO", "R", "D", "ER"],
        "outside": ["AW", "T", "S", "AY", "D"],
        "person": ["P", "ER", "S", "AH", "N"],
        "point": ["P", "OY", "N", "T"],
        "possible": ["P", "AA", "S", "AH", "B", "AH", "L"],
        "pretty": ["P", "R", "IH", "T", "IY"],
        "probably": ["P", "R", "AA", "B", "AH", "B", "L", "IY"],
        "problem": ["P", "R", "AA", "B", "L", "AH", "M"],
        "put": ["P", "UH", "T"],
        "question": ["K", "W", "EH", "S", "CH", "AH", "N"],
        "questions": ["K", "W", "EH", "S", "CH", "AH", "N", "Z"],
        "read": ["R", "IY", "D"],
        "ready": ["R", "EH", "D", "IY"],
        "real": ["R", "IY", "L"],
        "really": ["R", "IY", "L", "IY"],
        "reason": ["R", "IY", "Z", "AH", "N"],
        "remember": ["R", "IH", "M", "EH", "M", "B", "ER"],
        "room": ["R", "UW", "M"],
        "run": ["R", "AH", "N"],
        "saw": ["S", "AO"],
        "school": ["S", "K", "UW", "L"],
        "second": ["S", "EH", "K", "AH", "N", "D"],
        "seem": ["S", "IY", "M"],
        "seems": ["S", "IY", "M", "Z"],
        "seen": ["S", "IY", "N"],
        "set": ["S", "EH", "T"],
        "several": ["S", "EH", "V", "R", "AH", "L"],
        "side": ["S", "AY", "D"],
        "since": ["S", "IH", "N", "S"],
        "sit": ["S", "IH", "T"],
        "small": ["S", "M", "AO", "L"],
        "someone": ["S", "AH", "M", "W", "AH", "N"],
        "sometimes": ["S", "AH", "M", "T", "AY", "M", "Z"],
        "soon": ["S", "UW", "N"],
        "sorry": ["S", "AA", "R", "IY"],
        "sort": ["S", "AO", "R", "T"],
        "sound": ["S", "AW", "N", "D"],
        "sounds": ["S", "AW", "N", "D", "Z"],
        "speak": ["S", "P", "IY", "K"],
        "special": ["S", "P", "EH", "SH", "AH", "L"],
        "stand": ["S", "T", "AE", "N", "D"],
        "start": ["S", "T", "AA", "R", "T"],
        "state": ["S", "T", "EY", "T"],
        "stay": ["S", "T", "EY"],
        "stop": ["S", "T", "AA", "P"],
        "story": ["S", "T", "AO", "R", "IY"],
        "stuff": ["S", "T", "AH", "F"],
        "system": ["S", "IH", "S", "T", "AH", "M"],
        "talk": ["T", "AO", "K"],
        "talking": ["T", "AO", "K", "IH", "NG"],
        "terrible": ["T", "EH", "R", "AH", "B", "AH", "L"],
        "thinking": ["TH", "IH", "NG", "K", "IH", "NG"],
        "three": ["TH", "R", "IY"],
        "together": ["T", "AH", "G", "EH", "DH", "ER"],
        "told": ["T", "OW", "L", "D"],
        "tomorrow": ["T", "AH", "M", "AA", "R", "OW"],
        "tonight": ["T", "AH", "N", "AY", "T"],
        "took": ["T", "UH", "K"],
        "top": ["T", "AA", "P"],
        "tried": ["T", "R", "AY", "D"],
        "true": ["T", "R", "UW"],
        "try": ["T", "R", "AY"],
        "trying": ["T", "R", "AY", "IH", "NG"],
        "turn": ["T", "ER", "N"],
        "turned": ["T", "ER", "N", "D"],
        "understand": ["AH", "N", "D", "ER", "S", "T", "AE", "N", "D"],
        "until": ["AH", "N", "T", "IH", "L"],
        "used": ["Y", "UW", "Z", "D"],
        "using": ["Y", "UW", "Z", "IH", "NG"],
        "wait": ["W", "EY", "T"],
        "walk": ["W", "AO", "K"],
        "wanted": ["W", "AA", "N", "T", "IH", "D"],
        "watch": ["W", "AA", "CH"],
        "water": ["W", "AO", "T", "ER"],
        "week": ["W", "IY", "K"],
        "weeks": ["W", "IY", "K", "S"],
        "went": ["W", "EH", "N", "T"],
        "whether": ["W", "EH", "DH", "ER"],
        "whole": ["HH", "OW", "L"],
        "woman": ["W", "UH", "M", "AH", "N"],
        "women": ["W", "IH", "M", "AH", "N"],
        "wonder": ["W", "AH", "N", "D", "ER"],
        "wonderful": ["W", "AH", "N", "D", "ER", "F", "AH", "L"],
        "wont": ["W", "OW", "N", "T"],
        "working": ["W", "ER", "K", "IH", "NG"],
        "works": ["W", "ER", "K", "S"],
        "worry": ["W", "ER", "IY"],
        "worst": ["W", "ER", "S", "T"],
        "worth": ["W", "ER", "TH"],
        "wow": ["W", "AW"],
        "write": ["R", "AY", "T"],
        "wrong": ["R", "AO", "NG"],
        "yeah": ["Y", "AE"],
        "yep": ["Y", "EH", "P"],
        "yesterday": ["Y", "EH", "S", "T", "ER", "D", "EY"],
        "young": ["Y", "AH", "NG"],
        "yourself": ["Y", "AO", "R", "S", "EH", "L", "F"],
    ]
}
