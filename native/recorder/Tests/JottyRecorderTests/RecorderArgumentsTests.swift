import Testing

@testable import JottyRecorder

struct RecorderArgumentsTests {
  @Test
  func parsesAECQualitySpikeMode() {
    let arguments = RecorderArguments.parse(["--aec-spike", "/tmp/output"])

    #expect(arguments == RecorderArguments(outputDirectory: "/tmp/output", mode: .aecSpike))
  }

  @Test
  func preservesExistingModes() {
    #expect(
      RecorderArguments.parse(["/tmp/output"])
        == RecorderArguments(outputDirectory: "/tmp/output", mode: .archive)
    )
    #expect(
      RecorderArguments.parse(["--live", "/tmp/output"])
        == RecorderArguments(outputDirectory: "/tmp/output", mode: .live)
    )
  }
}
