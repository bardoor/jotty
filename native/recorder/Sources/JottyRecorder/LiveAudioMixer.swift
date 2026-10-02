import Foundation

protocol LiveAudioMixing: Sendable {
  func append(_ pcm: Data, source: LiveAudioSource) throws
  func finish(source: LiveAudioSource) throws
  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason)
}

final class LiveAudioMixer: LiveAudioMixing, @unchecked Sendable {
  enum Error: Swift.Error {
    case invalidPCM
  }

  private let packetWriter: PacketWriting
  private let lock = NSLock()
  private var buffers: [LiveAudioSource: Data] = [.system: Data(), .microphone: Data()]
  private var finished: Set<LiveAudioSource> = []
  private var enabled = true

  init(packetWriter: PacketWriting) {
    self.packetWriter = packetWriter
  }

  func append(_ pcm: Data, source: LiveAudioSource) throws {
    guard !pcm.isEmpty, pcm.count.isMultiple(of: MemoryLayout<Int16>.size) else {
      throw Error.invalidPCM
    }

    lock.lock()
    defer { lock.unlock() }

    guard enabled else {
      return
    }

    buffers[source, default: Data()].append(pcm)
    try emitPairedSamples()
  }

  func finish(source: LiveAudioSource) throws {
    lock.lock()
    defer { lock.unlock() }

    guard enabled else {
      return
    }

    finished.insert(source)
    try emitPairedSamples()

    guard finished == Set(LiveAudioSource.allCases) else {
      return
    }

    try emitRemainingSamples()
  }

  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason) {
    lock.lock()
    let firstFailure = enabled
    enabled = false
    buffers = [.system: Data(), .microphone: Data()]
    lock.unlock()

    guard firstFailure else {
      return
    }

    try? packetWriter.writeFailure(source: source, reason: reason)
  }

  private func emitPairedSamples() throws {
    let system = buffers[.system, default: Data()]
    let microphone = buffers[.microphone, default: Data()]
    let byteCount = min(system.count, microphone.count)

    guard byteCount > 0 else {
      return
    }

    try packetWriter.writePCM(Self.mix(system.prefix(byteCount), microphone.prefix(byteCount)))
    buffers[.system]!.removeFirst(byteCount)
    buffers[.microphone]!.removeFirst(byteCount)
  }

  private func emitRemainingSamples() throws {
    for source in LiveAudioSource.allCases {
      let pcm = buffers[source, default: Data()]

      if !pcm.isEmpty {
        try packetWriter.writePCM(pcm)
        buffers[source] = Data()
      }
    }
  }

  private static func mix(_ system: Data.SubSequence, _ microphone: Data.SubSequence) -> Data {
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
