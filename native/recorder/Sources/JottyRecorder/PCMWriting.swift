import Foundation

protocol PCMWriting: Sendable {
  func append(_ pcm: Data) throws
  func finish() throws
}
