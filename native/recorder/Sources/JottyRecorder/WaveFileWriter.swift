import AVFoundation
import Foundation

final class WaveFileWriter: PCMWriting, @unchecked Sendable {
  enum Error: Swift.Error {
    case outputFileAlreadyExists
    case invalidPCM
    case finished
    case cannotCreateBuffer
  }

  private let format = CanonicalPCMConverter.canonicalFormat()
  private var file: AVAudioFile?

  init(outputURL: URL) throws {
    guard !FileManager.default.fileExists(atPath: outputURL.path) else {
      throw Error.outputFileAlreadyExists
    }

    file = try AVAudioFile(
      forWriting: outputURL,
      settings: format.settings,
      commonFormat: .pcmFormatInt16,
      interleaved: true
    )
  }

  func append(_ pcm: Data) throws {
    guard !pcm.isEmpty, pcm.count.isMultiple(of: MemoryLayout<Int16>.size) else {
      throw Error.invalidPCM
    }

    guard let file else {
      throw Error.finished
    }

    let frameCount = AVAudioFrameCount(pcm.count / MemoryLayout<Int16>.size)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
      let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData
    else {
      throw Error.cannotCreateBuffer
    }

    buffer.frameLength = frameCount
    pcm.copyBytes(to: destination.assumingMemoryBound(to: UInt8.self), count: pcm.count)
    try file.write(from: buffer)
  }

  func finish() throws {
    file = nil
  }
}
