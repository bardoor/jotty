import AVFoundation
import CoreMedia
import Foundation

final class AudioFileWriter: @unchecked Sendable {
  enum Error: Swift.Error, LocalizedError {
    case cannotCreateWriter(Swift.Error)
    case cannotAddInput
    case cannotStartWriting(Swift.Error?)
    case cannotAppend(Swift.Error?)
    case noAudioSamples
    case cannotFinish(Swift.Error?)

    var errorDescription: String? {
      switch self {
      case .cannotCreateWriter(let error):
        "Cannot create audio writer: \(error.localizedDescription)"
      case .cannotAddInput:
        "Cannot add audio input to writer"
      case .cannotStartWriting(let error):
        "Cannot start audio writer: \(error?.localizedDescription ?? "unknown error")"
      case .cannotAppend(let error):
        "Cannot append audio sample: \(error?.localizedDescription ?? "unknown error")"
      case .noAudioSamples:
        "No audio samples were captured"
      case .cannotFinish(let error):
        "Cannot finish audio file: \(error?.localizedDescription ?? "unknown error")"
      }
    }
  }

  private let outputURL: URL
  private let lock = NSLock()
  private var assetWriter: AVAssetWriter?
  private var writerInput: AVAssetWriterInput?
  private var failure: Swift.Error?

  init(outputURL: URL) {
    self.outputURL = outputURL
  }

  func append(_ sampleBuffer: CMSampleBuffer) {
    lock.lock()
    defer { lock.unlock() }

    guard failure == nil else {
      return
    }

    do {
      if assetWriter == nil {
        try start(with: sampleBuffer)
      }

      guard let assetWriter, let writerInput else {
        return
      }

      guard writerInput.isReadyForMoreMediaData else {
        throw Error.cannotAppend(assetWriter.error)
      }

      guard writerInput.append(sampleBuffer) else {
        throw Error.cannotAppend(assetWriter.error)
      }
    } catch {
      failure = error
    }
  }

  func finish() async throws {
    let state = try prepareToFinish()

    await state.assetWriter.finishWriting()

    guard state.assetWriter.status == .completed else {
      throw Error.cannotFinish(state.assetWriter.error)
    }
  }

  private func start(with sampleBuffer: CMSampleBuffer) throws {
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      throw Error.cannotStartWriting(nil)
    }

    let assetWriter: AVAssetWriter

    do {
      assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
    } catch {
      throw Error.cannotCreateWriter(error)
    }

    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 32_000,
    ]
    let writerInput = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: outputSettings,
      sourceFormatHint: formatDescription
    )
    writerInput.expectsMediaDataInRealTime = true

    guard assetWriter.canAdd(writerInput) else {
      throw Error.cannotAddInput
    }

    assetWriter.add(writerInput)

    guard assetWriter.startWriting() else {
      throw Error.cannotStartWriting(assetWriter.error)
    }

    assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

    self.assetWriter = assetWriter
    self.writerInput = writerInput
  }

  private func prepareToFinish() throws -> (
    assetWriter: AVAssetWriter, writerInput: AVAssetWriterInput
  ) {
    lock.lock()
    defer { lock.unlock() }

    if let failure {
      throw failure
    }

    guard let assetWriter, let writerInput else {
      throw Error.noAudioSamples
    }

    writerInput.markAsFinished()
    return (assetWriter, writerInput)
  }
}
