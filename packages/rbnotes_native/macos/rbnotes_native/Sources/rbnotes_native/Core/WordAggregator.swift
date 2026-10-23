import Foundation

/// A single whisper sub-word token with its timing and probability. [text] is
/// the raw token string as returned by whisper.cpp (word-initial tokens are
/// prefixed with a space).
public struct WhisperTokenLite: Equatable {
  public let text: String
  public let t0Ms: Int
  public let t1Ms: Int
  public let p: Float

  public init(text: String, t0Ms: Int, t1Ms: Int, p: Float) {
    self.text = text
    self.t0Ms = t0Ms
    self.t1Ms = t1Ms
    self.p = p
  }
}

/// A word reconstructed from one or more [WhisperTokenLite]s.
public struct AggregatedWord: Equatable {
  public let text: String
  public let startMs: Int
  public let endMs: Int
  public let probability: Float

  public init(text: String, startMs: Int, endMs: Int, probability: Float) {
    self.text = text
    self.startMs = startMs
    self.endMs = endMs
    self.probability = probability
  }
}

/// Aggregates whisper sub-word tokens back into words.
///
/// Pure (Foundation only) so it can be unit-tested via `RbNativeCore`.
public enum WordAggregator {
  /// Merges [tokens] into words.
  ///
  /// A new word begins at a token whose raw text starts with whitespace
  /// (whisper prefixes word-initial tokens with a leading space); tokens
  /// without a leading space (e.g. sub-word continuations or trailing
  /// punctuation) attach to the current word. Whisper special tokens (text
  /// wrapped like `[_BEG_]`) and whitespace-only tokens are ignored. A word's
  /// [AggregatedWord.probability] is the arithmetic mean of its tokens'
  /// probabilities; its span is the first token's start to the last token's
  /// end.
  public static func aggregate(_ tokens: [WhisperTokenLite]) -> [AggregatedWord] {
    var words: [AggregatedWord] = []

    var buffer = ""
    var startMs = 0
    var endMs = 0
    var probs: [Float] = []

    func flush() {
      let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty, !probs.isEmpty {
        let mean = probs.reduce(0, +) / Float(probs.count)
        words.append(
          AggregatedWord(text: trimmed, startMs: startMs, endMs: endMs, probability: mean))
      }
      buffer = ""
      probs = []
    }

    for token in tokens {
      // Skip whisper special tokens and empty tokens.
      if token.text.isEmpty || token.text.hasPrefix("[_") { continue }

      let startsNewWord = token.text.first?.isWhitespace ?? false

      // A pure-whitespace token just closes the current word.
      if token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        flush()
        continue
      }

      if startsNewWord, !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        flush()
      }

      if probs.isEmpty {
        startMs = token.t0Ms
      }
      buffer += token.text
      endMs = token.t1Ms
      probs.append(token.p)
    }
    flush()

    return words
  }
}
