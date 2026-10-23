import AVFoundation
import Foundation
import whisper

/// A transcribed segment with start/end in milliseconds.
struct WhisperSegment {
  let startMs: Int
  let endMs: Int
  let text: String
}

/// Shared state passed to whisper.cpp C callbacks via `user_data`.
private final class WhisperCallbackBox {
  var onProgress: ((Double) -> Void)?
  var isCancelled: () -> Bool = { false }
}

/// Thin Swift wrapper over the whisper.cpp C API (Metal-backed).
///
/// Loads a model, runs `whisper_full` with a progress callback and an abort
/// callback wired to a cancellation flag, and extracts timestamped segments.
/// All work happens on the calling (background) thread.
enum WhisperBridge {
  /// Transcribes 16 kHz mono float samples. Throws `RbNativeError` on failure
  /// or cancellation.
  static func transcribe(
    samples: [Float],
    modelPath: String,
    language: String,
    onProgress: @escaping (Double) -> Void,
    isCancelled: @escaping () -> Bool
  ) throws -> [WhisperSegment] {
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw RbNativeError.modelMissing("model file not found: \(modelPath)")
    }

    var cparams = whisper_context_default_params()
    cparams.use_gpu = true  // Metal
    cparams.flash_attn = false

    guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
      throw RbNativeError.transcriptionFailed("failed to load whisper model")
    }
    defer { whisper_free(ctx) }

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

    // `language` must outlive the whisper_full call.
    let langCString = strdup(language)
    defer { free(langCString) }
    params.language = UnsafePointer(langCString)

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
      segments.append(
        WhisperSegment(
          startMs: Int(t0 * 10),
          endMs: Int(t1 * 10),
          text: text.trimmingCharacters(in: .whitespaces)))
    }
    return segments
  }

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
