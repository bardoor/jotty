import Foundation
import Testing

@testable import JottyRecorder

struct PacketWriterTests {
  @Test
  func serializesExactProtocolPackets() throws {
    let pipe = Pipe()
    let writer = PacketWriter(output: pipe.fileHandleForWriting)

    try writer.writeReady()
    try writer.writePCM(Data([0x34, 0x12]))
    try writer.writeFailure(source: .microphone, reason: .queueOverflow)
    try pipe.fileHandleForWriting.close()

    let bytes = pipe.fileHandleForReading.readDataToEndOfFile()

    #expect(
      bytes
        == Data([
          0x00, 0x00, 0x00, 0x01, 0x01,
          0x00, 0x00, 0x00, 0x03, 0x02, 0x34, 0x12,
          0x00, 0x00, 0x00, 0x03, 0x04, 0x02, 0x02,
        ])
    )
  }

  @Test
  func reportsClosedOutputPipeWithoutCrashing() throws {
    let pipe = Pipe()
    let writer = PacketWriter(outputDescriptor: pipe.fileHandleForWriting.fileDescriptor)
    try pipe.fileHandleForReading.close()

    #expect(throws: PacketWriter.WriteError.self) {
      try writer.writeReady()
    }
  }
}
