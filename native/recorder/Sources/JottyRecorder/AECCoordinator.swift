import CoreMedia
import Foundation

protocol AECProcessing: Sendable {
  func processRender(_ render: Data) throws
  func processCapture(_ capture: Data, delayMilliseconds: Int) throws -> Data
}

final class AECCoordinator: LiveAudioMixing, @unchecked Sendable {
  enum Error: Swift.Error {
    case invalidPCM
    case invalidPresentationTime
  }

  private struct TimedFrame {
    let pcm: Data
    let presentationTime: CMTime
  }

  private struct PCMFramer {
    private var buffer = Data()
    private var nextPresentationTime: CMTime?

    mutating func append(_ pcm: Data, presentationTime: CMTime) -> [TimedFrame] {
      if buffer.isEmpty {
        nextPresentationTime = presentationTime
      }
      buffer.append(pcm)

      var frames: [TimedFrame] = []
      while buffer.count >= AECCoordinator.frameBytes {
        let frameTime = nextPresentationTime ?? presentationTime
        frames.append(
          TimedFrame(
            pcm: Data(buffer.prefix(AECCoordinator.frameBytes)),
            presentationTime: frameTime
          )
        )
        buffer.removeFirst(AECCoordinator.frameBytes)
        nextPresentationTime = frameTime + AECCoordinator.frameDuration
      }
      return frames
    }
  }

  private static let frameBytes = 160 * MemoryLayout<Int16>.size
  private static let frameDuration = CMTime(value: 160, timescale: 16_000)

  private let processor: AECProcessing
  private let artifact: PCMWriting
  private let output: LiveAudioMixing
  private let lock = NSLock()
  private var framers: [LiveAudioSource: PCMFramer] = [
    .system: PCMFramer(),
    .microphone: PCMFramer(),
  ]
  private var pendingCapture: [TimedFrame] = []
  private var firstRenderTime: CMTime?
  private var latestRenderTime: CMTime?
  private var finished: Set<LiveAudioSource> = []
  private var enabled = true
  private var outputFinished = false

  init(processor: AECProcessing, artifact: PCMWriting, output: LiveAudioMixing) {
    self.processor = processor
    self.artifact = artifact
    self.output = output
  }

  func append(_ pcm: Data, source: LiveAudioSource, presentationTime: CMTime) throws {
    guard !pcm.isEmpty, pcm.count.isMultiple(of: MemoryLayout<Int16>.size) else {
      throw Error.invalidPCM
    }
    guard presentationTime.isValid else {
      throw Error.invalidPresentationTime
    }

    lock.lock()
    defer { lock.unlock() }

    guard enabled else {
      return
    }

    var framer = framers[source, default: PCMFramer()]
    let frames = framer.append(pcm, presentationTime: presentationTime)
    framers[source] = framer

    switch source {
    case .system:
      try processRender(frames)
    case .microphone:
      pendingCapture.append(contentsOf: frames)
    }

    try processReadyCapture()
  }

  func finish(source: LiveAudioSource) throws {
    lock.lock()
    defer { lock.unlock() }

    guard enabled, !outputFinished else {
      return
    }

    finished.insert(source)
    guard finished == Set(LiveAudioSource.allCases) else {
      return
    }

    try processReadyCapture()
    pendingCapture.removeAll()
    try artifact.finish()
    try output.finish(source: .system)
    try output.finish(source: .microphone)
    outputFinished = true
  }

  func finalize() throws {
    try output.finalize()
  }

  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason) {
    lock.lock()
    let firstFailure = enabled
    enabled = false
    pendingCapture.removeAll()
    try? artifact.finish()
    lock.unlock()

    guard firstFailure else {
      return
    }

    output.fail(source: source, reason: reason)
  }

  private func processRender(_ frames: [TimedFrame]) throws {
    for frame in frames {
      try processor.processRender(frame.pcm)
      try output.append(frame.pcm, source: .system, presentationTime: frame.presentationTime)
      if firstRenderTime == nil {
        firstRenderTime = frame.presentationTime
      }
      latestRenderTime = frame.presentationTime
    }
  }

  private func processReadyCapture() throws {
    guard let firstRenderTime, let latestRenderTime else {
      return
    }

    while let frame = pendingCapture.first,
      CMTimeCompare(frame.presentationTime, latestRenderTime) <= 0
    {
      pendingCapture.removeFirst()
      guard CMTimeCompare(frame.presentationTime, firstRenderTime) >= 0 else {
        continue
      }

      let cleaned = try processor.processCapture(frame.pcm, delayMilliseconds: 0)
      try artifact.append(cleaned)
      try output.append(cleaned, source: .microphone, presentationTime: frame.presentationTime)
    }
  }
}
