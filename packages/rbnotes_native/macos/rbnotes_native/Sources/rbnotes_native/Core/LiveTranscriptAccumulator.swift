import Foundation

/// Accumulates the text of consecutive, overlapping live-transcription windows
/// into one cleaned transcript, de-duplicating the words the windows share.
///
/// Consecutive audio windows overlap by ~1 s, which whisper re-transcribes, so
/// each new window's leading words usually repeat the tail of what we already
/// have. [append] detects the longest such word overlap and keeps only the new
/// remainder.
///
/// Pure (Foundation only) so it can be unit-tested via `RbNativeCore`.
public struct LiveTranscriptAccumulator {
  /// The accumulated words, in order.
  public private(set) var words: [String] = []

  /// Upper bound on how many words of overlap to look for (keeps matching cheap
  /// and avoids spurious long-range matches).
  private let maxOverlapWords: Int

  public init(maxOverlapWords: Int = 40) {
    self.maxOverlapWords = maxOverlapWords
  }

  /// The accumulated transcript so far.
  public var text: String { words.joined(separator: " ") }

  /// Appends the transcript [chunk] of a newly transcribed window, removing the
  /// overlap it shares with the tail of the current transcript.
  public mutating func append(_ chunk: String) {
    let incoming = Self.tokenize(chunk)
    guard !incoming.isEmpty else { return }
    guard !words.isEmpty else {
      words = incoming
      return
    }
    let skip = Self.overlapLength(tail: words, head: incoming, maxWindow: maxOverlapWords)
    if skip < incoming.count {
      words.append(contentsOf: incoming[skip...])
    }
  }

  // MARK: - Pure helpers (exposed for testing)

  /// Splits [text] into words on whitespace.
  public static func tokenize(_ text: String) -> [String] {
    text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
  }

  /// The largest `k` in `1...maxWindow` such that the last `k` normalized words
  /// of [tail] equal the first `k` normalized words of [head]; 0 if there is no
  /// overlap.
  public static func overlapLength(tail: [String], head: [String], maxWindow: Int) -> Int {
    let maxK = min(maxWindow, tail.count, head.count)
    var k = maxK
    while k > 0 {
      var match = true
      for i in 0..<k where normalize(tail[tail.count - k + i]) != normalize(head[i]) {
        match = false
        break
      }
      if match { return k }
      k -= 1
    }
    return 0
  }

  /// Lowercases and strips edge punctuation so "Olá," and "olá" compare equal.
  public static func normalize(_ word: String) -> String {
    word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
  }
}
