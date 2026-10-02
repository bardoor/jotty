import Foundation
import Testing
@testable import JottyRecorder

@Suite("Timed callback operation")
struct TimedCallbackOperationTests {
  @Test("times out when the framework drops its completion callback")
  func timesOutWithoutCallback() async {
    await #expect(throws: TimedCallbackOperation.Timeout.self) {
      try await TimedCallbackOperation.run(timeout: .milliseconds(10)) { _completion in }
    }
  }
}
