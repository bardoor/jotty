import Foundation
import Testing

@testable import JottyRecorder

struct PacketWriterTests {
  @Test
  func serializesExactProtocolPackets() throws {
    let pipe = Pipe()
    let writer = PacketWriter(output: pipe.fileHandleForWriting)

    try writer.writeReady()
    try writer.writePCM(Data([0x34, 0x12]), source: .system)
    try writer.writePCM(Data([0x78, 0x56]), source: .microphone)
    try writer.writeFailure(source: .microphone, reason: .queueOverflow)
    try pipe.fileHandleForWriting.close()

    let bytes = pipe.fileHandleForReading.readDataToEndOfFile()

    #expect(
      bytes
        == Data([
          0x00, 0x00, 0x00, 0x01, 0x01,
          0x00, 0x00, 0x00, 0x03, 0x02, 0x34, 0x12,
          0x00, 0x00, 0x00, 0x03, 0x03, 0x78, 0x56,
          0x00, 0x00, 0x00, 0x03, 0x04, 0x02, 0x02,
        ])
    )
  }
}
