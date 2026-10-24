import AVFoundation
import Foundation
import sherpa_onnx

/// Local speaker diarization (Phase 3, option F) over a mono wav using the
/// sherpa-onnx offline pipeline: pyannote segmentation → 3dspeaker (CAM++)
/// embeddings → fast clustering. Runs off the main thread (the caller routes it
/// onto a background queue) and returns speaker turns ordered by start time.
///
/// The models are managed by `DiarizationModelManager`; the native libraries
/// come from `sherpa_onnx.xcframework`/`onnxruntime.xcframework`
/// (`scripts/build_sherpa.sh`).
enum Diarization {
  /// Runs diarization on [wavPath]. [numSpeakers] pins the cluster count when
  /// known (> 0); nil lets the clustering decide via a distance threshold.
  /// Throws `diarization_model_missing`, `invalid_argument` or
  /// `diarization_failed`.
  static func run(wavPath: String, numSpeakers: Int?) throws -> [[String: Any]] {
    guard DiarizationModelManager.shared.isDownloaded else {
      throw RbNativeError.diarizationModelMissing("diarization models not downloaded")
    }
    guard FileManager.default.fileExists(atPath: wavPath) else {
      throw RbNativeError.invalidArgument("audio file not found: \(wavPath)")
    }

    let samples = try read16kMono(wavPath: wavPath)
    guard !samples.isEmpty else { return [] }

    let segPath = DiarizationModelManager.shared.segmentationPath
    let embPath = DiarizationModelManager.shared.embeddingPath
    let threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))

    // C strings must outlive the create call; sherpa copies them internally.
    let segC = strdup(segPath)
    let embC = strdup(embPath)
    let providerC = strdup("cpu")
    defer {
      free(segC)
      free(embC)
      free(providerC)
    }

    var config = SherpaOnnxOfflineSpeakerDiarizationConfig()
    config.segmentation.pyannote.model = UnsafePointer(segC)
    config.segmentation.num_threads = threads
    config.segmentation.provider = UnsafePointer(providerC)
    config.embedding.model = UnsafePointer(embC)
    config.embedding.num_threads = threads
    config.embedding.provider = UnsafePointer(providerC)
    if let numSpeakers, numSpeakers > 0 {
      config.clustering.num_clusters = Int32(numSpeakers)
    } else {
      config.clustering.num_clusters = -1
      config.clustering.threshold = 0.5
    }
    config.min_duration_on = 0.3
    config.min_duration_off = 0.5

    guard let sd = SherpaOnnxCreateOfflineSpeakerDiarization(&config) else {
      throw RbNativeError.diarizationFailed("failed to create diarization pipeline")
    }
    defer { SherpaOnnxDestroyOfflineSpeakerDiarization(sd) }

    let result: OpaquePointer? = samples.withUnsafeBufferPointer { buf in
      SherpaOnnxOfflineSpeakerDiarizationProcess(sd, buf.baseAddress, Int32(buf.count))
    }
    guard let result else {
      throw RbNativeError.diarizationFailed("diarization produced no result")
    }
    defer { SherpaOnnxOfflineSpeakerDiarizationDestroyResult(result) }

    let count = Int(SherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments(result))
    guard count > 0, let segments = SherpaOnnxOfflineSpeakerDiarizationResultSortByStartTime(result)
    else {
      return []
    }
    defer { SherpaOnnxOfflineSpeakerDiarizationDestroySegment(segments) }

    var turns: [[String: Any]] = []
    turns.reserveCapacity(count)
    for i in 0..<count {
      let seg = segments[i]
      turns.append([
        "startMs": Int((seg.start * 1000).rounded()),
        "endMs": Int((seg.end * 1000).rounded()),
        "speaker": Int(seg.speaker),
      ])
    }
    let numSpeakers = SherpaOnnxOfflineSpeakerDiarizationResultGetNumSpeakers(result)
    RbLog.diarization.info(
      "diarized \(count, privacy: .public) segments across \(numSpeakers, privacy: .public) speakers")
    return turns
  }

  /// Reads [wavPath] into 16 kHz mono float samples (resampling if needed, as
  /// the models require 16 kHz). Throws `invalid_argument` on read failure.
  private static func read16kMono(wavPath: String) throws -> [Float] {
    let url = URL(fileURLWithPath: wavPath)
    do {
      let file = try AVAudioFile(forReading: url)
      let srcFormat = file.processingFormat
      let length = AVAudioFrameCount(file.length)
      guard length > 0,
        let inBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: length)
      else { return [] }
      try file.read(into: inBuffer)

      // Already 16 kHz mono float → downmix and return directly.
      if Int(srcFormat.sampleRate) == 16_000 {
        return downmix(inBuffer)
      }

      guard
        let outFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
        let converter = AVAudioConverter(from: srcFormat, to: outFormat)
      else {
        // Fall back to the raw (downmixed) samples if resampling is unavailable.
        return downmix(inBuffer)
      }
      let ratio = 16_000.0 / srcFormat.sampleRate
      let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1024
      guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity)
      else { return [] }

      var fed = false
      var error: NSError?
      converter.convert(to: outBuffer, error: &error) { _, outStatus in
        if fed {
          outStatus.pointee = .noDataNow
          return nil
        }
        fed = true
        outStatus.pointee = .haveData
        return inBuffer
      }
      if let error {
        throw RbNativeError.invalidArgument("cannot resample wav: \(error.localizedDescription)")
      }
      guard let channel = outBuffer.floatChannelData else { return [] }
      return Array(UnsafeBufferPointer(start: channel[0], count: Int(outBuffer.frameLength)))
    } catch let error as RbNativeError {
      throw error
    } catch {
      throw RbNativeError.invalidArgument("cannot read wav: \(error.localizedDescription)")
    }
  }

  private static func downmix(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let channel = buffer.floatChannelData else { return [] }
    let channels = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)
    if channels == 1 {
      return Array(UnsafeBufferPointer(start: channel[0], count: frames))
    }
    var mono = [Float](repeating: 0, count: frames)
    for c in 0..<channels {
      let data = channel[c]
      for f in 0..<frames { mono[f] += data[f] / Float(channels) }
    }
    return mono
  }
}
