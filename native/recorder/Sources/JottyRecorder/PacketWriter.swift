import Darwin
import Foundation

protocol PacketWriting: Sendable {
  func writeReady() throws
  func writePCM(_ pcm: Data) throws
  func writeFailure(source: LiveAudioSource, reason: LiveAudioFailureReason) throws
}

enum LiveAudioSource: UInt8, CaseIterable, Sendable, Equatable {
  case system = 0x01
  case microphone = 0x02
}

enum LiveAudioFailureReason: UInt8, Sendable, Equatable {
  case conversion = 0x01
  case queueOverflow = 0x02
  case packetOutput = 0x03
}

final class PacketWriter: PacketWriting, @unchecked Sendable {
  struct WriteError: Error {
    let code: Int32
  }

  private let outputDescriptor: Int32
  private let lock = NSLock()

  init(output: FileHandle) {
    self.outputDescriptor = output.fileDescriptor
    signal(SIGPIPE, SIG_IGN)
  }

  init(outputDescriptor: Int32) {
    self.outputDescriptor = outputDescriptor
    signal(SIGPIPE, SIG_IGN)
  }

  func writeReady() throws {
    try write(payload: Data([0x01]))
  }

  func writePCM(_ pcm: Data) throws {
    precondition(!pcm.isEmpty)

    var payload = Data([0x02])
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

    try write(packet)
  }

  private func write(_ data: Data) throws {
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var written = 0

      while written < bytes.count {
        let count = Darwin.write(outputDescriptor, baseAddress.advanced(by: written), bytes.count - written)

        if count > 0 {
          written += count
        } else if count < 0 && errno != EINTR {
          throw WriteError(code: errno)
        }
      }
    }
  }
}
