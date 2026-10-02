import CoreMedia
import Foundation

protocol AECProcessing: Sendable {
  func processRender(_ render: Data) throws
  func processCapture(_ capture: Data, delayMilliseconds: Int) throws -> Data
}

protocol PCMWriting: Sendable {
  func append(_ pcm: Data) throws
  func finish() throws
}

final class AECQualityCoordinator: LiveAudioMixing, @unchecked Sendable {
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
      while buffer.count >= AECQualityCoordinator.frameBytes {
        let frameTime = nextPresentationTime ?? presentationTime
        frames.append(
          TimedFrame(
            pcm: Data(buffer.prefix(AECQualityCoordinator.frameBytes)),
            presentationTime: frameTime
          )
        )
        buffer.removeFirst(AECQualityCoordinator.frameBytes)
        nextPresentationTime = frameTime + AECQualityCoordinator.frameDuration
      }
      return frames
    }
  }

  private static let frameBytes = 160 * MemoryLayout<Int16>.size
  private static let frameDuration = CMTime(value: 160, timescale: 16_000)

  private let processor: AECProcessing
  private let writer: PCMWriting
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
  private var writerFinished = false

  init(processor: AECProcessing, writer: PCMWriting) {
    self.processor = processor
    self.writer = writer
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

    guard enabled, !writerFinished else {
      return
    }

    finished.insert(source)
    guard finished == Set(LiveAudioSource.allCases) else {
      return
    }

    try processReadyCapture()
    try writer.finish()
    writerFinished = true
  }

  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason) {
    lock.lock()
    enabled = false
    pendingCapture.removeAll()
    lock.unlock()
  }

  private func processRender(_ frames: [TimedFrame]) throws {
    for frame in frames {
      try processor.processRender(frame.pcm)
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

      let output = try processor.processCapture(frame.pcm, delayMilliseconds: 0)
      try writer.append(output)
    }
  }
}
