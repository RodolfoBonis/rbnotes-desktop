import AVFoundation
import Foundation
import whisper

/// A transcribed segment with start/end in milliseconds and optional per-word
/// timing/confidence (populated only when word timestamps were requested).
struct WhisperSegment {
  let startMs: Int
  let endMs: Int
  let text: String
  let words: [AggregatedWord]
}

/// Shared state passed to whisper.cpp C callbacks via `user_data`.
private final class WhisperCallbackBox {
  var onProgress: ((Double) -> Void)?
  var isCancelled: () -> Bool = { false }
}

/// Minimum RMS energy (0..1) for audio to be considered speech. Below this the
/// clip is treated as silence and transcription returns an empty list instead
/// of risking a hallucinated segment.
private let kSilenceRMSThreshold = 0.004

/// A loaded, reusable whisper.cpp context for one model file. Not thread-safe:
/// the owner must serialize `run` calls. `lastUsed` supports idle eviction.
final class WhisperContext {
  let modelPath: String
  private let ctx: OpaquePointer
  private(set) var lastUsed = Date()

  init(modelPath: String) throws {
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw RbNativeError.modelMissing("model file not found: \(modelPath)")
    }
    var cparams = whisper_context_default_params()
    cparams.use_gpu = true  // Metal
    cparams.flash_attn = false
    guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
      throw RbNativeError.transcriptionFailed("failed to load whisper model")
    }
    self.ctx = ctx
    self.modelPath = modelPath
    let name = (modelPath as NSString).lastPathComponent
    RbLog.whisper.info("loaded whisper context for \(name, privacy: .public)")
  }

  deinit {
    let name = (modelPath as NSString).lastPathComponent
    whisper_free(ctx)
    RbLog.whisper.info("freed whisper context for \(name, privacy: .public)")
  }

  /// Runs `whisper_full` on 16 kHz mono float samples. Treats near-silence as
  /// an empty result. Throws `transcription_cancelled`/`transcription_failed`.
  ///
  /// - Parameters:
  ///   - initialPrompt: seeds the decoder with vocabulary/context
  ///     (`whisper_full_params.initial_prompt`).
  ///   - wordTimestamps: when true, enables token-level timestamps and
  ///     aggregates tokens back into `WhisperSegment.words`.
  func run(
    samples: [Float],
    language: String,
    initialPrompt: String? = nil,
    wordTimestamps: Bool = false,
    onProgress: @escaping (Double) -> Void = { _ in },
    isCancelled: @escaping () -> Bool = { false }
  ) throws -> [WhisperSegment] {
    lastUsed = Date()
    guard !samples.isEmpty else { return [] }

    // Silence / blank guard: avoid whisper hallucinating on near-silent clips.
    if Self.rms(samples) < kSilenceRMSThreshold {
      RbLog.whisper.info("audio below silence threshold; returning empty transcript")
      return []
    }

    let box = WhisperCallbackBox()
    box.onProgress = onProgress
    box.isCancelled = isCancelled
    let boxPtr = Unmanaged.passUnretained(box).toOpaque()

    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    let cpuCount = ProcessInfo.processInfo.activeProcessorCount
    params.n_threads = Int32(max(1, min(8, cpuCount - 1)))
    params.print_progress = false
    params.print_realtime = false
    params.print_timestamps = false
    params.translate = false
    params.no_context = true
    params.single_segment = false
    params.suppress_blank = true
    params.no_speech_thold = 0.6  // skip segments whisper flags as non-speech
    params.token_timestamps = wordTimestamps

    params.progress_callback = { _, _, progress, userData in
      guard let userData else { return }
      let box = Unmanaged<WhisperCallbackBox>.fromOpaque(userData).takeUnretainedValue()
      box.onProgress?(Double(progress) / 100.0)
    }
    params.progress_callback_user_data = boxPtr

    params.abort_callback = { userData in
      guard let userData else { return false }
      let box = Unmanaged<WhisperCallbackBox>.fromOpaque(userData).takeUnretainedValue()
      return box.isCancelled()
    }
    params.abort_callback_user_data = boxPtr

    // `language` and `initial_prompt` must outlive the whisper_full call.
    // "auto" makes whisper.cpp detect the language and then transcribe. Never
    // set `detect_language`: it means "detect only and return", which made
    // every note on "Detectar automaticamente" come out with no transcript.
    let langCString = strdup(language)
    defer { free(langCString) }
    params.language = UnsafePointer(langCString)
    params.detect_language = false

    let promptCString: UnsafeMutablePointer<CChar>? =
      (initialPrompt?.isEmpty == false) ? strdup(initialPrompt!) : nil
    defer { if let promptCString { free(promptCString) } }
    if let promptCString { params.initial_prompt = UnsafePointer(promptCString) }

    let result = samples.withUnsafeBufferPointer { buffer -> Int32 in
      whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
    }

    if isCancelled() {
      throw RbNativeError.transcriptionCancelled("transcription cancelled")
    }
    guard result == 0 else {
      throw RbNativeError.transcriptionFailed("whisper_full returned \(result)")
    }

    let count = whisper_full_n_segments(ctx)
    var segments: [WhisperSegment] = []
    segments.reserveCapacity(Int(count))
    for i in 0..<count {
      let t0 = whisper_full_get_segment_t0(ctx, i)  // 10ms units
      let t1 = whisper_full_get_segment_t1(ctx, i)
      let text = String(cString: whisper_full_get_segment_text(ctx, i))
      let words = wordTimestamps ? aggregateWords(segment: i) : []
      segments.append(
        WhisperSegment(
          startMs: Int(t0 * 10),
          endMs: Int(t1 * 10),
          text: text.trimmingCharacters(in: .whitespaces),
          words: words))
    }
    return segments
  }

  /// Reads the tokens of [segment], drops whisper special tokens and aggregates
  /// the rest into words via `WordAggregator`.
  private func aggregateWords(segment i: Int32) -> [AggregatedWord] {
    let eot = whisper_token_eot(ctx)
    let nTokens = whisper_full_n_tokens(ctx, i)
    var tokens: [WhisperTokenLite] = []
    tokens.reserveCapacity(Int(nTokens))
    for j in 0..<nTokens {
      let data = whisper_full_get_token_data(ctx, i, j)
      if data.id >= eot { continue }  // special token (eot/sot/timestamps/…)
      let text = String(cString: whisper_full_get_token_text(ctx, i, j))
      tokens.append(
        WhisperTokenLite(
          text: text, t0Ms: Int(data.t0 * 10), t1Ms: Int(data.t1 * 10), p: data.p))
    }
    return WordAggregator.aggregate(tokens)
  }

  private static func rms(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }
    var sum = 0.0
    for s in samples { sum += Double(s) * Double(s) }
    return (sum / Double(samples.count)).squareRoot()
  }
}

/// Thin Swift wrapper over the whisper.cpp C API (Metal-backed) for reading
/// audio. Context loading/execution lives in `WhisperContext`.
enum WhisperBridge {
  /// Reads a 16 kHz mono wav into float samples suitable for whisper.
  static func readSamples(wavPath: String) throws -> [Float] {
    let url = URL(fileURLWithPath: wavPath)
    guard FileManager.default.fileExists(atPath: wavPath) else {
      throw RbNativeError.transcriptionFailed("wav not found: \(wavPath)")
    }
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      let length = AVAudioFrameCount(file.length)
      guard length > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length)
      else { return [] }
      try file.read(into: buffer)
      guard let channel = buffer.floatChannelData else { return [] }
      // Downmix to mono if needed.
      let channelCount = Int(format.channelCount)
      let frames = Int(buffer.frameLength)
      if channelCount == 1 {
        return Array(UnsafeBufferPointer(start: channel[0], count: frames))
      }
      var mono = [Float](repeating: 0, count: frames)
      for c in 0..<channelCount {
        let data = channel[c]
        for f in 0..<frames { mono[f] += data[f] / Float(channelCount) }
      }
      return mono
    } catch let error as RbNativeError {
      throw error
    } catch {
      throw RbNativeError.transcriptionFailed("cannot read wav: \(error.localizedDescription)")
    }
  }
}
