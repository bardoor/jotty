import JottyAEC

let frameSamples = Int(JOTTY_AEC_FRAME_SAMPLES)
let processor = jotty_aec_create()
precondition(processor != nil, "AEC processor creation failed")
defer { jotty_aec_destroy(processor) }

var render = [Int16](repeating: 0, count: frameSamples)
var capture = [Int16](repeating: 0, count: frameSamples)
var output = [Int16](repeating: -1, count: frameSamples)

func processRender(_ samples: inout [Int16], count: Int? = nil) -> Int32 {
  samples.withUnsafeBufferPointer { buffer in
    jotty_aec_process_render(processor, buffer.baseAddress, count ?? buffer.count)
  }
}

func processCapture(_ samples: inout [Int16], output: inout [Int16]) -> Int32 {
  samples.withUnsafeBufferPointer { inputBuffer in
    output.withUnsafeMutableBufferPointer { outputBuffer in
      jotty_aec_process_capture(
        processor,
        inputBuffer.baseAddress,
        inputBuffer.count,
        0,
        outputBuffer.baseAddress
      )
    }
  }
}

precondition(processRender(&render) == 0, "silence render processing failed")
let silenceResult = processCapture(&capture, output: &output)
precondition(silenceResult == 0, "silence capture processing failed with \(silenceResult)")
precondition(output.allSatisfy { $0 == 0 }, "silence produced non-zero samples")

for index in 0..<frameSamples {
  render[index] = index % 40 < 20 ? 1_000 : -1_000
  capture[index] = render[index]
}

precondition(processRender(&render) == 0, "non-zero render processing failed")
let signalResult = processCapture(&capture, output: &output)
precondition(signalResult == 0, "non-zero capture processing failed with \(signalResult)")

let invalidFrameResult = processRender(&render, count: render.count - 1)
precondition(
  invalidFrameResult == JOTTY_AEC_INVALID_FRAME_SIZE,
  "invalid frame size was accepted"
)

let invalidArgumentResult = jotty_aec_process_capture(processor, nil, frameSamples, 0, nil)
precondition(
  invalidArgumentResult == JOTTY_AEC_INVALID_ARGUMENT,
  "null frame pointers were accepted"
)

print("AEC bridge smoke passed: \(frameSamples) samples at \(JOTTY_AEC_SAMPLE_RATE) Hz")
