// NarrationCheck.swift
// Decides whether a language model's rewording of a line may be shown in
// its place. The model may change the words, never the advice: a rewrite
// is accepted only when it carries exactly the numbers of the original
// (each as often, in any order) and stays within a length cap. Anything
// else falls back to the original line.

import Foundation

public enum NarrationCheck {

    /// Longest rewrite shown; a push body gets hard to read past it.
    public static let defaultMaxLength = 140

    /// True when `candidate` may replace `original`.
    public static func accepts(_ candidate: String, for original: String,
                               maxLength: Int = defaultMaxLength) -> Bool {
        let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxLength else { return false }
        return numbers(in: text) == numbers(in: original)
            && numberWords(in: text) == numberWords(in: original)
    }

    /// Every number written in digits, as written, sorted: "8.0 km ·
    /// 5:25–5:45/km" gives ["5:25", "5:45", "8.0"]. A decimal point or a
    /// colon joins digits into one number; anything else separates them.
    static func numbers(in text: String) -> [String] {
        let chars = Array(text)
        var found: [String] = []
        var i = 0
        while i < chars.count {
            guard isDigit(chars[i]) else { i += 1; continue }
            var j = i + 1
            while j < chars.count {
                if isDigit(chars[j]) {
                    j += 1
                } else if chars[j] == "." || chars[j] == ":", j + 1 < chars.count, isDigit(chars[j + 1]) {
                    j += 1
                } else {
                    break
                }
            }
            found.append(String(chars[i..<j]))
            i = j
        }
        return found.sorted()
    }

    /// Numbers written as English words ("six", "twenty", "second",
    /// "twice"), sorted. A
    /// rewrite that spells out a number, or adds one in words, changes
    /// what the line says.
    static func numberWords(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { cardinalWords.contains($0) }
            .sorted()
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static let cardinalWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
        "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "dozen",
        "first", "second", "third", "fourth", "fifth", "twice", "double", "triple", "half",
    ]
}
