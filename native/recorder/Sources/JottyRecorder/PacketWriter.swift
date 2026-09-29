import Foundation

protocol PacketWriting: Sendable {
  func writeReady() throws
  func writePCM(_ pcm: Data, source: LiveAudioSource) throws
  func writeFailure(source: LiveAudioSource, reason: LiveAudioFailureReason) throws
}

enum LiveAudioSource: UInt8, Sendable, Equatable {
  case system = 0x01
  case microphone = 0x02

  var packetKind: UInt8 {
    switch self {
    case .system:
      0x02
    case .microphone:
      0x03
    }
  }
}

enum LiveAudioFailureReason: UInt8, Sendable, Equatable {
  case conversion = 0x01
  case queueOverflow = 0x02
  case packetOutput = 0x03
}

final class PacketWriter: PacketWriting, @unchecked Sendable {
  private let output: FileHandle
  private let lock = NSLock()

  init(output: FileHandle) {
    self.output = output
  }

  func writeReady() throws {
    try write(payload: Data([0x01]))
  }

  func writePCM(_ pcm: Data, source: LiveAudioSource) throws {
    precondition(!pcm.isEmpty)

    var payload = Data([source.packetKind])
    payload.append(pcm)
    try write(payload: payload)
  }

  func writeFailure(source: LiveAudioSource, reason: LiveAudioFailureReason) throws {
    try write(payload: Data([0x04, source.rawValue, reason.rawValue]))
  }

  private func write(payload: Data) throws {
    precondition(payload.count <= Int(UInt32.max))

    var length = UInt32(payload.count).bigEndian
    var packet = withUnsafeBytes(of: &length) { Data($0) }
    packet.append(payload)

    lock.lock()
    defer { lock.unlock() }

    try output.write(contentsOf: packet)
  }
}
