import Foundation
import XCTest

@testable import RbNativeCore

final class WordAggregatorTests: XCTestCase {
  private func tok(_ text: String, _ t0: Int, _ t1: Int, _ p: Float) -> WhisperTokenLite {
    WhisperTokenLite(text: text, t0Ms: t0, t1Ms: t1, p: p)
  }

  func testJoinsSubwordTokensIntoWords() {
    // " hel" + "lo" -> "hello"; " wor" + "ld" -> "world".
    let tokens = [
      tok(" hel", 0, 100, 0.9),
      tok("lo", 100, 200, 0.8),
      tok(" wor", 200, 320, 0.6),
      tok("ld", 320, 400, 0.4),
    ]
    let words = WordAggregator.aggregate(tokens)
    XCTAssertEqual(words.map(\.text), ["hello", "world"])
    XCTAssertEqual(words[0].startMs, 0)
    XCTAssertEqual(words[0].endMs, 200)
    XCTAssertEqual(words[1].startMs, 200)
    XCTAssertEqual(words[1].endMs, 400)
  }

  func testProbabilityIsMeanOfTokens() {
    let tokens = [tok(" ab", 0, 50, 1.0), tok("c", 50, 100, 0.5)]
    let words = WordAggregator.aggregate(tokens)
    XCTAssertEqual(words.count, 1)
    XCTAssertEqual(words[0].probability, 0.75, accuracy: 1e-6)
  }

  func testFirstTokenWithoutLeadingSpaceStartsWord() {
    let tokens = [tok("Olá", 0, 120, 0.95), tok(" mundo", 120, 300, 0.9)]
    let words = WordAggregator.aggregate(tokens)
    XCTAssertEqual(words.map(\.text), ["Olá", "mundo"])
  }

  func testPunctuationAttachesToPrecedingWord() {
    let tokens = [
      tok(" tudo", 0, 100, 0.9),
      tok(" bem", 100, 200, 0.9),
      tok(".", 200, 210, 0.9),
    ]
    let words = WordAggregator.aggregate(tokens)
    XCTAssertEqual(words.map(\.text), ["tudo", "bem."])
  }

  func testSkipsSpecialAndWhitespaceTokens() {
    let tokens = [
      tok("[_BEG_]", 0, 0, 0.0),
      tok(" olá", 0, 100, 0.9),
      tok(" ", 100, 100, 0.0),
      tok("tchau", 100, 200, 0.8),
    ]
    let words = WordAggregator.aggregate(tokens)
    // The whitespace token closes "olá"; "tchau" (no leading space) is its own word
    // because the previous word was already flushed.
    XCTAssertEqual(words.map(\.text), ["olá", "tchau"])
  }

  func testEmptyInputYieldsNoWords() {
    XCTAssertTrue(WordAggregator.aggregate([]).isEmpty)
  }
}
