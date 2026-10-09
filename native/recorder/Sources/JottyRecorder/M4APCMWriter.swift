import AVFoundation
import Foundation

final class M4APCMWriter: PCMWriting, @unchecked Sendable {
  enum Error: Swift.Error {
    case cannotCreateBuffer
    case invalidPCM
  }

  private let lock = NSLock()
  private var file: AVAudioFile?

  init(outputURL: URL) throws {
    let format = CanonicalPCMConverter.canonicalFormat()
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 32_000,
    ]

    file = try AVAudioFile(
      forWriting: outputURL,
      settings: settings,
      commonFormat: format.commonFormat,
      interleaved: format.isInterleaved
    )
  }

  func append(_ pcm: Data) throws {
    guard !pcm.isEmpty, pcm.count.isMultiple(of: MemoryLayout<Int16>.size) else {
      throw Error.invalidPCM
    }

    lock.lock()
    defer { lock.unlock() }

    guard let file else {
      return
    }

    let format = CanonicalPCMConverter.canonicalFormat()
    let frames = AVAudioFrameCount(pcm.count / MemoryLayout<Int16>.size)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
      let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData
    else {
      throw Error.cannotCreateBuffer
    }

    buffer.frameLength = frames
    pcm.copyBytes(to: destination.assumingMemoryBound(to: UInt8.self), count: pcm.count)
    try file.write(from: buffer)
  }

  func finish() throws {
    lock.lock()
    file = nil
    lock.unlock()
  }
}
