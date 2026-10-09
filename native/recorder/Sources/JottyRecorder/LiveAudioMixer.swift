import CoreMedia
import Foundation

protocol LiveAudioMixing: Sendable {
  func append(_ pcm: Data, source: LiveAudioSource, presentationTime: CMTime) throws
  func finish(source: LiveAudioSource) throws
  func finalize() throws
  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason)
}

extension LiveAudioMixing {
  func finalize() throws {}
}

final class LiveAudioMixer: LiveAudioMixing, @unchecked Sendable {
  enum Error: Swift.Error {
    case invalidPCM
    case invalidPresentationTime
    case discontinuousTimeline
  }

  private struct TimelineBuffer {
    private(set) var startSample: Int64?
    private var pcm = Data()

    var sampleCount: Int {
      pcm.count / MemoryLayout<Int16>.size
    }

    var isEmpty: Bool {
      pcm.isEmpty
    }

    mutating func append(_ data: Data, at sample: Int64) throws {
      if let startSample {
        guard sample == startSample + Int64(sampleCount) else {
          throw Error.discontinuousTimeline
        }
      } else {
        startSample = sample
      }

      pcm.append(data)
    }

    mutating func consume(_ count: Int) -> Data {
      let byteCount = count * MemoryLayout<Int16>.size
      let output = Data(pcm.prefix(byteCount))
      pcm.removeFirst(byteCount)

      if pcm.isEmpty {
        startSample = nil
      } else {
        startSample! += Int64(count)
      }

      return output
    }
  }

  private let packetWriter: PacketWriting
  private let playbackWriter: PCMWriting?
  private let lock = NSLock()
  private var buffers: [LiveAudioSource: TimelineBuffer] = [
    .system: TimelineBuffer(),
    .microphone: TimelineBuffer(),
  ]
  private var finished: Set<LiveAudioSource> = []
  private var enabled = true
  private var failure: Swift.Error?

  init(packetWriter: PacketWriting, playbackWriter: PCMWriting? = nil) {
    self.packetWriter = packetWriter
    self.playbackWriter = playbackWriter
  }

  func append(_ pcm: Data, source: LiveAudioSource, presentationTime: CMTime) throws {
    guard !pcm.isEmpty, pcm.count.isMultiple(of: MemoryLayout<Int16>.size) else {
      throw Error.invalidPCM
    }
    guard presentationTime.isValid, !presentationTime.isIndefinite else {
      throw Error.invalidPresentationTime
    }

    let sample = CMTimeConvertScale(
      presentationTime,
      timescale: 16_000,
      method: .roundHalfAwayFromZero
    ).value

    lock.lock()
    defer { lock.unlock() }

    guard enabled else {
      return
    }

    try buffers[source, default: TimelineBuffer()].append(pcm, at: sample)
    try emitAlignedSamples()
  }

  func finish(source: LiveAudioSource) throws {
    lock.lock()
    defer { lock.unlock() }

    guard enabled else {
      return
    }

    finished.insert(source)
    try emitAlignedSamples()

    guard finished == Set(LiveAudioSource.allCases) else {
      return
    }

    do {
      try emitRemainingSamples()
      try playbackWriter?.finish()
    } catch {
      failure = error
      throw error
    }
  }

  func finalize() throws {
    lock.lock()
    defer { lock.unlock() }

    if let failure {
      throw failure
    }
  }

  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason) {
    lock.lock()
    let firstFailure = enabled
    enabled = false
    buffers = [.system: TimelineBuffer(), .microphone: TimelineBuffer()]
    lock.unlock()

    guard firstFailure else {
      return
    }

    try? packetWriter.writeFailure(source: source, reason: reason)
  }

  private func emit(_ pcm: Data) throws {
    try packetWriter.writePCM(pcm)

    do {
      try playbackWriter?.append(pcm)
    } catch {
      failure = error
      throw error
    }
  }

  private func emitAlignedSamples() throws {
    var system = buffers[.system, default: TimelineBuffer()]
    var microphone = buffers[.microphone, default: TimelineBuffer()]

    while let systemStart = system.startSample,
      let microphoneStart = microphone.startSample
    {
      if systemStart < microphoneStart {
        let count = min(system.sampleCount, Int(microphoneStart - systemStart))
        try emit(system.consume(count))
      } else if microphoneStart < systemStart {
        let count = min(microphone.sampleCount, Int(systemStart - microphoneStart))
        try emit(microphone.consume(count))
      } else {
        let count = min(system.sampleCount, microphone.sampleCount)
        try emit(Self.mix(system.consume(count), microphone.consume(count)))
      }
    }

    buffers[.system] = system
    buffers[.microphone] = microphone
  }

  private func emitRemainingSamples() throws {
    for source in LiveAudioSource.allCases {
      var buffer = buffers[source, default: TimelineBuffer()]
      if !buffer.isEmpty {
        try emit(buffer.consume(buffer.sampleCount))
        buffers[source] = buffer
      }
    }
  }

  private static func mix(_ system: Data, _ microphone: Data) -> Data {
    var output = Data(capacity: system.count)
    let systemBytes = Array(system)
    let microphoneBytes = Array(microphone)

    for index in stride(from: 0, to: systemBytes.count, by: 2) {
      let systemSample = sample(low: systemBytes[index], high: systemBytes[index + 1])
      let microphoneSample = sample(low: microphoneBytes[index], high: microphoneBytes[index + 1])
      let mixed = Int16(clamping: Int32(systemSample) + Int32(microphoneSample))
      let bits = UInt16(bitPattern: mixed)
      output.append(UInt8(truncatingIfNeeded: bits))
      output.append(UInt8(truncatingIfNeeded: bits >> 8))
    }

    return output
  }

  private static func sample(low: UInt8, high: UInt8) -> Int16 {
    Int16(bitPattern: UInt16(low) | UInt16(high) << 8)
  }
}
