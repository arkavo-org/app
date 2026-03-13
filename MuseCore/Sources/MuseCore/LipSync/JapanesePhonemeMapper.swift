//
//  JapanesePhonemeMapper.swift
//  AvatarMuse
//
//  Copyright 2025 Arkavo
//

import Foundation

// MARK: - Japanese Phoneme Mapper

/// Converts Japanese text (hiragana/katakana/romaji) to viseme sequences
/// Uses mora-based timing for natural Japanese speech rhythm
public struct JapanesePhonemeMapper: Sendable {

    /// Silence marker for pauses
    public static let silenceMarker = "SIL"

    /// Duration of one mora at normal speech rate (seconds)
    public static let moraDuration: Double = 0.120

    public init() {}

    // MARK: - Public API

    /// Convert Japanese text to phoneme sequence
    /// - Parameter text: Japanese text (hiragana, katakana, kanji, or romaji)
    /// - Returns: Array of phoneme strings
    public func convert(_ text: String) -> [String] {
        var phonemes: [String] = []
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let char = chars[i]

            // Check for small tsu (促音) - doubles next consonant
            if char == "っ" || char == "ッ" {
                phonemes.append("Q")  // Geminate marker
                i += 1
                continue
            }

            // Check for long vowel marker
            if char == "ー" {
                // Extend previous vowel
                if let last = phonemes.last, isVowelPhoneme(last) {
                    phonemes.append(last)
                }
                i += 1
                continue
            }

            // Try to match kana (with possible small kana following)
            if let (moraPhonemes, consumed) = matchKana(chars: chars, position: i) {
                phonemes.append(contentsOf: moraPhonemes)
                i += consumed
                continue
            }

            // Try romaji
            if char.isASCII {
                if let (romajiPhonemes, consumed) = matchRomaji(chars: chars, position: i) {
                    phonemes.append(contentsOf: romajiPhonemes)
                    i += consumed
                    continue
                }
            }

            // Punctuation = silence
            if char.isPunctuation || char == "、" || char == "。" || char == "！" || char == "？" {
                phonemes.append(Self.silenceMarker)
                i += 1
                continue
            }

            // Skip unknown characters (kanji without reading, etc.)
            i += 1
        }

        return phonemes
    }

    /// Create a viseme timeline from Japanese text
    /// - Parameters:
    ///   - text: Japanese text
    ///   - speechRate: Speech rate multiplier (1.0 = normal)
    /// - Returns: VisemeTimeline
    public func createTimeline(text: String, speechRate: Float = 0.48) -> VisemeTimeline {
        let phonemes = convert(text)
        var timeline = VisemeTimeline()
        var currentTime: Double = 0

        // Adjust mora duration based on speech rate
        let rateMultiplier = 1.0 / Double(max(speechRate, 0.1)) * 0.5

        for phoneme in phonemes {
            let viseme = mapToViseme(phoneme)
            let duration = estimateDuration(phoneme) * rateMultiplier

            let timedViseme = TimedViseme(
                viseme: viseme,
                startTime: currentTime,
                duration: duration
            )
            timeline.append(timedViseme)
            currentTime += duration
        }

        return timeline
    }

    // MARK: - Viseme Mapping

    /// Map Japanese phoneme to VRM viseme
    private func mapToViseme(_ phoneme: String) -> VRMViseme {
        switch phoneme {
        // Vowels
        case "A": return .aa   // あ
        case "I": return .ih   // い (closer to ih than ee for Japanese)
        case "U": return .ou   // う
        case "E": return .ee   // え
        case "O": return .oh   // お

        // Consonants with inherent vowel quality
        case "K", "G", "S", "Z", "T", "D", "N", "H", "B", "P", "M", "Y", "R", "W":
            return .neutral

        // Special
        case "Q": return .neutral  // Geminate (closed mouth pause)
        case "N_": return .neutral  // Syllabic N (ん)
        case Self.silenceMarker: return .neutral

        default: return .neutral
        }
    }

    /// Estimate duration for a phoneme
    private func estimateDuration(_ phoneme: String) -> Double {
        switch phoneme {
        case "A", "I", "U", "E", "O":
            return Self.moraDuration  // Full mora for vowels
        case "Q":
            return Self.moraDuration  // Geminate takes one mora
        case "N_":
            return Self.moraDuration  // Syllabic N takes one mora
        case Self.silenceMarker:
            return Self.moraDuration * 1.5  // Pause is slightly longer
        default:
            return Self.moraDuration * 0.3  // Consonants are brief
        }
    }

    private func isVowelPhoneme(_ phoneme: String) -> Bool {
        ["A", "I", "U", "E", "O"].contains(phoneme)
    }

    // MARK: - Kana Matching

    /// Match hiragana/katakana at position
    private func matchKana(chars: [Character], position: Int) -> ([String], Int)? {
        let char = chars[position]
        let remaining = chars.count - position

        // Check for compound kana (きゃ, しゅ, etc.)
        if remaining >= 2 {
            let nextChar = chars[position + 1]
            if isSmallKana(nextChar) {
                if let compound = compoundKanaMap[String([char, nextChar])] {
                    return (compound, 2)
                }
            }
        }

        // Single kana
        if let phonemes = kanaMap[char] {
            return (phonemes, 1)
        }

        return nil
    }

    private func isSmallKana(_ char: Character) -> Bool {
        "ゃゅょャュョぁぃぅぇぉァィゥェォ".contains(char)
    }

    /// Match romaji at position
    private func matchRomaji(chars: [Character], position: Int) -> ([String], Int)? {
        let remaining = chars.count - position

        // Try longest matches first
        for len in stride(from: min(3, remaining), through: 1, by: -1) {
            let substr = String(chars[position..<position+len]).lowercased()
            if let phonemes = romajiMap[substr] {
                return (phonemes, len)
            }
        }

        return nil
    }

    // MARK: - Mapping Tables

    /// Hiragana/Katakana to phoneme mapping
    private let kanaMap: [Character: [String]] = [
        // Vowels
        "あ": ["A"], "ア": ["A"],
        "い": ["I"], "イ": ["I"],
        "う": ["U"], "ウ": ["U"],
        "え": ["E"], "エ": ["E"],
        "お": ["O"], "オ": ["O"],

        // K-row
        "か": ["K", "A"], "カ": ["K", "A"],
        "き": ["K", "I"], "キ": ["K", "I"],
        "く": ["K", "U"], "ク": ["K", "U"],
        "け": ["K", "E"], "ケ": ["K", "E"],
        "こ": ["K", "O"], "コ": ["K", "O"],

        // S-row
        "さ": ["S", "A"], "サ": ["S", "A"],
        "し": ["S", "I"], "シ": ["S", "I"],
        "す": ["S", "U"], "ス": ["S", "U"],
        "せ": ["S", "E"], "セ": ["S", "E"],
        "そ": ["S", "O"], "ソ": ["S", "O"],

        // T-row
        "た": ["T", "A"], "タ": ["T", "A"],
        "ち": ["T", "I"], "チ": ["T", "I"],
        "つ": ["T", "U"], "ツ": ["T", "U"],
        "て": ["T", "E"], "テ": ["T", "E"],
        "と": ["T", "O"], "ト": ["T", "O"],

        // N-row
        "な": ["N", "A"], "ナ": ["N", "A"],
        "に": ["N", "I"], "ニ": ["N", "I"],
        "ぬ": ["N", "U"], "ヌ": ["N", "U"],
        "ね": ["N", "E"], "ネ": ["N", "E"],
        "の": ["N", "O"], "ノ": ["N", "O"],

        // H-row
        "は": ["H", "A"], "ハ": ["H", "A"],
        "ひ": ["H", "I"], "ヒ": ["H", "I"],
        "ふ": ["H", "U"], "フ": ["H", "U"],
        "へ": ["H", "E"], "ヘ": ["H", "E"],
        "ほ": ["H", "O"], "ホ": ["H", "O"],

        // M-row
        "ま": ["M", "A"], "マ": ["M", "A"],
        "み": ["M", "I"], "ミ": ["M", "I"],
        "む": ["M", "U"], "ム": ["M", "U"],
        "め": ["M", "E"], "メ": ["M", "E"],
        "も": ["M", "O"], "モ": ["M", "O"],

        // Y-row
        "や": ["Y", "A"], "ヤ": ["Y", "A"],
        "ゆ": ["Y", "U"], "ユ": ["Y", "U"],
        "よ": ["Y", "O"], "ヨ": ["Y", "O"],

        // R-row
        "ら": ["R", "A"], "ラ": ["R", "A"],
        "り": ["R", "I"], "リ": ["R", "I"],
        "る": ["R", "U"], "ル": ["R", "U"],
        "れ": ["R", "E"], "レ": ["R", "E"],
        "ろ": ["R", "O"], "ロ": ["R", "O"],

        // W-row
        "わ": ["W", "A"], "ワ": ["W", "A"],
        "を": ["O"], "ヲ": ["O"],

        // N (syllabic)
        "ん": ["N_"], "ン": ["N_"],

        // Voiced (G-row)
        "が": ["G", "A"], "ガ": ["G", "A"],
        "ぎ": ["G", "I"], "ギ": ["G", "I"],
        "ぐ": ["G", "U"], "グ": ["G", "U"],
        "げ": ["G", "E"], "ゲ": ["G", "E"],
        "ご": ["G", "O"], "ゴ": ["G", "O"],

        // Voiced (Z-row)
        "ざ": ["Z", "A"], "ザ": ["Z", "A"],
        "じ": ["Z", "I"], "ジ": ["Z", "I"],
        "ず": ["Z", "U"], "ズ": ["Z", "U"],
        "ぜ": ["Z", "E"], "ゼ": ["Z", "E"],
        "ぞ": ["Z", "O"], "ゾ": ["Z", "O"],

        // Voiced (D-row)
        "だ": ["D", "A"], "ダ": ["D", "A"],
        "ぢ": ["D", "I"], "ヂ": ["D", "I"],
        "づ": ["D", "U"], "ヅ": ["D", "U"],
        "で": ["D", "E"], "デ": ["D", "E"],
        "ど": ["D", "O"], "ド": ["D", "O"],

        // Voiced (B-row)
        "ば": ["B", "A"], "バ": ["B", "A"],
        "び": ["B", "I"], "ビ": ["B", "I"],
        "ぶ": ["B", "U"], "ブ": ["B", "U"],
        "べ": ["B", "E"], "ベ": ["B", "E"],
        "ぼ": ["B", "O"], "ボ": ["B", "O"],

        // Semi-voiced (P-row)
        "ぱ": ["P", "A"], "パ": ["P", "A"],
        "ぴ": ["P", "I"], "ピ": ["P", "I"],
        "ぷ": ["P", "U"], "プ": ["P", "U"],
        "ぺ": ["P", "E"], "ペ": ["P", "E"],
        "ぽ": ["P", "O"], "ポ": ["P", "O"],
    ]

    /// Compound kana (with small ya/yu/yo)
    private let compoundKanaMap: [String: [String]] = [
        // K + y
        "きゃ": ["K", "Y", "A"], "キャ": ["K", "Y", "A"],
        "きゅ": ["K", "Y", "U"], "キュ": ["K", "Y", "U"],
        "きょ": ["K", "Y", "O"], "キョ": ["K", "Y", "O"],

        // S + y (sh sounds)
        "しゃ": ["S", "Y", "A"], "シャ": ["S", "Y", "A"],
        "しゅ": ["S", "Y", "U"], "シュ": ["S", "Y", "U"],
        "しょ": ["S", "Y", "O"], "ショ": ["S", "Y", "O"],

        // T + y (ch sounds)
        "ちゃ": ["T", "Y", "A"], "チャ": ["T", "Y", "A"],
        "ちゅ": ["T", "Y", "U"], "チュ": ["T", "Y", "U"],
        "ちょ": ["T", "Y", "O"], "チョ": ["T", "Y", "O"],

        // N + y
        "にゃ": ["N", "Y", "A"], "ニャ": ["N", "Y", "A"],
        "にゅ": ["N", "Y", "U"], "ニュ": ["N", "Y", "U"],
        "にょ": ["N", "Y", "O"], "ニョ": ["N", "Y", "O"],

        // H + y
        "ひゃ": ["H", "Y", "A"], "ヒャ": ["H", "Y", "A"],
        "ひゅ": ["H", "Y", "U"], "ヒュ": ["H", "Y", "U"],
        "ひょ": ["H", "Y", "O"], "ヒョ": ["H", "Y", "O"],

        // M + y
        "みゃ": ["M", "Y", "A"], "ミャ": ["M", "Y", "A"],
        "みゅ": ["M", "Y", "U"], "ミュ": ["M", "Y", "U"],
        "みょ": ["M", "Y", "O"], "ミョ": ["M", "Y", "O"],

        // R + y
        "りゃ": ["R", "Y", "A"], "リャ": ["R", "Y", "A"],
        "りゅ": ["R", "Y", "U"], "リュ": ["R", "Y", "U"],
        "りょ": ["R", "Y", "O"], "リョ": ["R", "Y", "O"],

        // G + y
        "ぎゃ": ["G", "Y", "A"], "ギャ": ["G", "Y", "A"],
        "ぎゅ": ["G", "Y", "U"], "ギュ": ["G", "Y", "U"],
        "ぎょ": ["G", "Y", "O"], "ギョ": ["G", "Y", "O"],

        // Z + y (j sounds)
        "じゃ": ["Z", "Y", "A"], "ジャ": ["Z", "Y", "A"],
        "じゅ": ["Z", "Y", "U"], "ジュ": ["Z", "Y", "U"],
        "じょ": ["Z", "Y", "O"], "ジョ": ["Z", "Y", "O"],

        // B + y
        "びゃ": ["B", "Y", "A"], "ビャ": ["B", "Y", "A"],
        "びゅ": ["B", "Y", "U"], "ビュ": ["B", "Y", "U"],
        "びょ": ["B", "Y", "O"], "ビョ": ["B", "Y", "O"],

        // P + y
        "ぴゃ": ["P", "Y", "A"], "ピャ": ["P", "Y", "A"],
        "ぴゅ": ["P", "Y", "U"], "ピュ": ["P", "Y", "U"],
        "ぴょ": ["P", "Y", "O"], "ピョ": ["P", "Y", "O"],
    ]

    /// Romaji to phoneme mapping
    private let romajiMap: [String: [String]] = [
        // Vowels
        "a": ["A"], "i": ["I"], "u": ["U"], "e": ["E"], "o": ["O"],

        // K-row
        "ka": ["K", "A"], "ki": ["K", "I"], "ku": ["K", "U"], "ke": ["K", "E"], "ko": ["K", "O"],

        // S-row
        "sa": ["S", "A"], "si": ["S", "I"], "shi": ["S", "I"], "su": ["S", "U"], "se": ["S", "E"], "so": ["S", "O"],

        // T-row
        "ta": ["T", "A"], "ti": ["T", "I"], "chi": ["T", "I"], "tu": ["T", "U"], "tsu": ["T", "U"], "te": ["T", "E"], "to": ["T", "O"],

        // N-row
        "na": ["N", "A"], "ni": ["N", "I"], "nu": ["N", "U"], "ne": ["N", "E"], "no": ["N", "O"],
        "n": ["N_"],

        // H-row
        "ha": ["H", "A"], "hi": ["H", "I"], "hu": ["H", "U"], "fu": ["H", "U"], "he": ["H", "E"], "ho": ["H", "O"],

        // M-row
        "ma": ["M", "A"], "mi": ["M", "I"], "mu": ["M", "U"], "me": ["M", "E"], "mo": ["M", "O"],

        // Y-row
        "ya": ["Y", "A"], "yu": ["Y", "U"], "yo": ["Y", "O"],

        // R-row
        "ra": ["R", "A"], "ri": ["R", "I"], "ru": ["R", "U"], "re": ["R", "E"], "ro": ["R", "O"],

        // W-row
        "wa": ["W", "A"], "wo": ["O"],

        // Voiced
        "ga": ["G", "A"], "gi": ["G", "I"], "gu": ["G", "U"], "ge": ["G", "E"], "go": ["G", "O"],
        "za": ["Z", "A"], "zi": ["Z", "I"], "ji": ["Z", "I"], "zu": ["Z", "U"], "ze": ["Z", "E"], "zo": ["Z", "O"],
        "da": ["D", "A"], "di": ["D", "I"], "du": ["D", "U"], "de": ["D", "E"], "do": ["D", "O"],
        "ba": ["B", "A"], "bi": ["B", "I"], "bu": ["B", "U"], "be": ["B", "E"], "bo": ["B", "O"],
        "pa": ["P", "A"], "pi": ["P", "I"], "pu": ["P", "U"], "pe": ["P", "E"], "po": ["P", "O"],

        // Compound (y-sounds)
        "kya": ["K", "Y", "A"], "kyu": ["K", "Y", "U"], "kyo": ["K", "Y", "O"],
        "sha": ["S", "Y", "A"], "shu": ["S", "Y", "U"], "sho": ["S", "Y", "O"],
        "cha": ["T", "Y", "A"], "chu": ["T", "Y", "U"], "cho": ["T", "Y", "O"],
        "nya": ["N", "Y", "A"], "nyu": ["N", "Y", "U"], "nyo": ["N", "Y", "O"],
        "hya": ["H", "Y", "A"], "hyu": ["H", "Y", "U"], "hyo": ["H", "Y", "O"],
        "mya": ["M", "Y", "A"], "myu": ["M", "Y", "U"], "myo": ["M", "Y", "O"],
        "rya": ["R", "Y", "A"], "ryu": ["R", "Y", "U"], "ryo": ["R", "Y", "O"],
        "gya": ["G", "Y", "A"], "gyu": ["G", "Y", "U"], "gyo": ["G", "Y", "O"],
        "ja": ["Z", "Y", "A"], "ju": ["Z", "Y", "U"], "jo": ["Z", "Y", "O"],
        "bya": ["B", "Y", "A"], "byu": ["B", "Y", "U"], "byo": ["B", "Y", "O"],
        "pya": ["P", "Y", "A"], "pyu": ["P", "Y", "U"], "pyo": ["P", "Y", "O"],
    ]
}
