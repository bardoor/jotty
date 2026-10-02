import CoreGraphics
import Foundation
import ScreenCaptureKit

final class AudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
  let queue: DispatchQueue
  private let writer: AudioFileWriter
  private let liveEmitter: LiveAudioEmitter?

  init(label: String, outputURL: URL, liveEmitter: LiveAudioEmitter?) {
    queue = DispatchQueue(label: label)
    writer = AudioFileWriter(outputURL: outputURL)
    self.liveEmitter = liveEmitter
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else {
      return
    }

    append(sampleBuffer)
  }

  func append(_ sampleBuffer: CMSampleBuffer) {
    writer.append(sampleBuffer)
    liveEmitter?.process(sampleBuffer)
  }

  func finish() async throws {
    liveEmitter?.finish()
    try await writer.finish()
  }
}

final class Recorder: NSObject, SCStreamDelegate, @unchecked Sendable {
  private static let captureOperationTimeout = Duration.seconds(10)

  enum Error: Swift.Error, LocalizedError {
    case mainDisplayNotFound
    case stoppedUnexpectedly(Swift.Error)

    var errorDescription: String? {
      switch self {
      case .mainDisplayNotFound:
        "Cannot find the main display"
      case .stoppedUnexpectedly(let error):
        "Capture stopped unexpectedly: \(error.localizedDescription)"
      }
    }
  }

  private let systemOutput: AudioStreamOutput
  private let microphoneOutput: AudioStreamOutput
  private var stream: SCStream?
  private var streamFailure: Swift.Error?
  private let failureLock = NSLock()
  private let onFailure: @Sendable (Swift.Error) -> Void

  init(
    paths: RecordingPaths,
    liveOutput: PacketWriting?,
    onFailure: @escaping @Sendable (Swift.Error) -> Void
  ) {
    self.onFailure = onFailure
    let liveMixer = liveOutput.map(LiveAudioMixer.init)
    systemOutput = AudioStreamOutput(
      label: "dev.jotty.recorder.system-audio",
      outputURL: paths.systemAudio,
      liveEmitter: liveMixer.map {
        LiveAudioEmitter(
          source: .system,
          converter: CanonicalPCMConverter(),
          mixer: $0
        )
      }
    )
    microphoneOutput = AudioStreamOutput(
      label: "dev.jotty.recorder.microphone",
      outputURL: paths.microphoneAudio,
      liveEmitter: liveMixer.map {
        LiveAudioEmitter(
          source: .microphone,
          converter: CanonicalPCMConverter(),
          mixer: $0
        )
      }
    )
  }

  func start() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )

    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
      throw Error.mainDisplayNotFound
    }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let configuration = SCStreamConfiguration()
    configuration.width = 2
    configuration.height = 2
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    configuration.queueDepth = 1
    configuration.capturesAudio = true
    configuration.sampleRate = 48_000
    configuration.channelCount = 1
    configuration.captureMicrophone = true
    configuration.excludesCurrentProcessAudio = true

    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(
      systemOutput,
      type: .audio,
      sampleHandlerQueue: systemOutput.queue
    )
    try stream.addStreamOutput(
      microphoneOutput,
      type: .microphone,
      sampleHandlerQueue: microphoneOutput.queue
    )

    self.stream = stream
    try await TimedCallbackOperation.run(timeout: Self.captureOperationTimeout) { completion in
      stream.startCapture(completionHandler: completion)
    }
  }

  func stop() async throws {
    guard let stream else {
      return
    }

    var captureError: Swift.Error?

    if capturedStreamFailure() == nil {
      do {
        try await TimedCallbackOperation.run(timeout: Self.captureOperationTimeout) { completion in
          stream.stopCapture(completionHandler: completion)
        }
      } catch {
        captureError = error
      }
    }

    do {
      async let systemFinish: Void = systemOutput.finish()
      async let microphoneFinish: Void = microphoneOutput.finish()
      _ = try await (systemFinish, microphoneFinish)
    } catch {
      throw captureError ?? capturedStreamFailure() ?? error
    }

    self.stream = nil

    if let error = captureError ?? capturedStreamFailure() {
      throw error
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Swift.Error) {
    failureLock.lock()
    let firstFailure = streamFailure == nil

    if firstFailure {
      streamFailure = Error.stoppedUnexpectedly(error)
    }

    failureLock.unlock()

    if firstFailure {
      onFailure(Error.stoppedUnexpectedly(error))
    }
  }

  private func capturedStreamFailure() -> Swift.Error? {
    failureLock.lock()
    defer { failureLock.unlock() }
    return streamFailure
  }
}
