import Testing

@testable import JottyRecorder

struct RecorderArgumentsTests {
  @Test
  func rejectsDiagnosticModes() {
    #expect(RecorderArguments.parse(["--aec-spike", "/tmp/output"]) == nil)
  }

  @Test
  func preservesExistingModes() {
    #expect(
      RecorderArguments.parse(["/tmp/output"])
        == RecorderArguments(outputDirectory: "/tmp/output", mode: .archive, microphoneDeviceID: nil)
    )
    #expect(
      RecorderArguments.parse(["--live", "/tmp/output"])
        == RecorderArguments(outputDirectory: "/tmp/output", mode: .live, microphoneDeviceID: nil)
    )
  }

  @Test
  func acceptsConcreteMicrophoneForLiveCapture() {
    #expect(
      RecorderArguments.parse(["--live", "--microphone-device-id", "device-1", "/tmp/output"])
        == RecorderArguments(outputDirectory: "/tmp/output", mode: .live, microphoneDeviceID: "device-1")
    )
  }
}
