import Foundation

// MARK: - Fuzzy Matching Utilities

/// Lightweight fuzzy matcher tuned for command palettes and small lists.
///
/// Supports:
/// - Multi-token queries (space separated)
/// - Exact / prefix / word-start boosts
/// - Subsequence fuzzy matching with gap penalties + consecutive bonuses
enum FuzzyMatcher {
  /// Returns a score if `queryTokens` all match the `target`. Higher is better.
  static func score(queryTokens: [String], target: String) -> Int? {
    let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedTarget.isEmpty { return nil }

    let targetLower = trimmedTarget.lowercased()

    var total = 0
    for token in queryTokens {
      let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.isEmpty { continue }

      guard let tokenScore = scoreSingleToken(query: t, targetLower: targetLower) else {
        return nil
      }
      total += tokenScore
    }

    return total
  }

  private static func scoreSingleToken(query: String, targetLower: String) -> Int? {
    let q = query.lowercased()

    // Exact
    if targetLower == q {
      return 2000
    }

    // Prefix
    if targetLower.hasPrefix(q) {
      // Slightly prefer shorter targets for the same prefix.
      return 1500 - min(200, max(0, targetLower.count - q.count))
    }

    // Word-start / boundary prefix
    let words = splitWords(targetLower)
    if words.contains(where: { $0.hasPrefix(q) }) {
      return 1100
    }

    // Subsequence fuzzy
    return subsequenceScore(query: q, targetLower: targetLower)
  }

  private static func splitWords(_ s: String) -> [Substring] {
    s.split { ch in
      ch == " " || ch == "\t" || ch == "\n" || ch == "-" || ch == "_" || ch == ":" || ch == "/" || ch == "." || ch == "," || ch == "(" || ch == ")" || ch == "[" || ch == "]"
    }
  }

  /// Basic subsequence match with scoring.
  /// - Matches in order are required.
  /// - Consecutive matches get a bonus.
  /// - Large gaps get penalized.
  private static func subsequenceScore(query: String, targetLower: String) -> Int? {
    if query.isEmpty { return nil }

    var qIndex = query.startIndex
    var lastMatchedOffset: Int? = nil

    var score = 0
    var consecutive = 0

    for (offset, ch) in targetLower.enumerated() {
      if qIndex == query.endIndex { break }
      if query[qIndex] == ch {
        // Base point for a match.
        score += 10

        // Bonus for consecutive matches.
        if let last = lastMatchedOffset, last + 1 == offset {
          consecutive += 1
          score += 15 + min(30, consecutive * 3)
        } else {
          consecutive = 0
          // Small bonus for earlier matches.
          score += max(0, 20 - min(20, offset))
        }

        // Penalize gaps a bit so tighter matches rank higher.
        if let last = lastMatchedOffset {
          let gap = offset - last - 1
          if gap > 0 {
            score -= min(25, gap * 2)
          }
        }

        lastMatchedOffset = offset
        qIndex = query.index(after: qIndex)
      }
    }

    guard qIndex == query.endIndex else { return nil }
    return max(1, score)
  }
}

// MARK: - Palette Query Parsing

struct PaletteQuery {
  var searchText: String
  var searchTokens: [String]
  var projectFilter: String?

  /// Parses a query string for:
  /// - free text tokens
  /// - optional `in:<project>` / `project:<project>` token for project filtering
  static func parse(_ raw: String) -> PaletteQuery {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return PaletteQuery(searchText: "", searchTokens: [], projectFilter: nil)
    }

    let parts = trimmed.split(separator: " ").map(String.init)
    var remaining: [String] = []
    var project: String? = nil

    for p in parts {
      if p.lowercased().hasPrefix("in:") {
        let v = String(p.dropFirst(3))
        if !v.isEmpty { project = v }
        continue
      }
      if p.lowercased().hasPrefix("project:") {
        let v = String(p.dropFirst(8))
        if !v.isEmpty { project = v }
        continue
      }
      remaining.append(p)
    }

    let text = remaining.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let tokens = remaining

    return PaletteQuery(searchText: text, searchTokens: tokens, projectFilter: project)
  }
}
