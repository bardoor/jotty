import Foundation
import Testing
@testable import JottyRecorder

@Suite("Termination waiter")
struct TerminationWaiterTests {
  private struct StreamStopped: Error, Equatable {}

  @Test("delivers a stream failure that arrives before waiting")
  func deliversEarlyFailure() async {
    let waiter = TerminationWaiter(monitorInterrupt: false, parentPID: nil, inputDescriptor: nil)
    waiter.fail(StreamStopped())

    await #expect(throws: StreamStopped.self) {
      try await waiter.wait()
    }
  }

  @Test("fails when the recorder loses its parent process")
  func detectsParentExit() async {
    let waiter = TerminationWaiter(
      monitorInterrupt: false,
      parentPID: -1,
      parentCheckInterval: .milliseconds(10),
      inputDescriptor: nil
    )

    await #expect(throws: TerminationWaiter.ParentExited.self) {
      try await waiter.wait()
    }
  }

  @Test("fails when the owning port closes its input pipe")
  func detectsInputClosure() async throws {
    let pipe = Pipe()
    let waiter = TerminationWaiter(
      monitorInterrupt: false,
      parentPID: nil,
      inputDescriptor: pipe.fileHandleForReading.fileDescriptor
    )
    try pipe.fileHandleForWriting.close()

    await #expect(throws: TerminationWaiter.ParentExited.self) {
      try await waiter.wait()
    }
  }
}
