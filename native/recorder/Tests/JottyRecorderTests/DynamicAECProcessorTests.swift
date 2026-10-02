import Foundation
import Testing

@testable import JottyRecorder

struct DynamicAECProcessorTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["JOTTY_AEC_TEST_LIBRARY"] != nil))
  func loadsBridgeAndProcessesOneFrame() throws {
    let libraryPath = try #require(ProcessInfo.processInfo.environment["JOTTY_AEC_TEST_LIBRARY"])
    let processor = try DynamicAECProcessor(libraryPath: libraryPath)
    let frame = Data(repeating: 0, count: 160 * MemoryLayout<Int16>.size)

    try processor.processRender(frame)
    let output = try processor.processCapture(frame, delayMilliseconds: 0)

    #expect(output == frame)
  }
}
