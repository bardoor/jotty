import Testing

@testable import JottyRecorder

struct PermissionErrorTests {
  @Test
  func screenCaptureGrantRequiresTerminalRelaunch() {
    #expect(
      PermissionError.screenCaptureRelaunchRequired.errorDescription
        == "Screen recording permission was granted. Fully quit and reopen the terminal, then run Jotty Recorder again."
    )
  }
}
