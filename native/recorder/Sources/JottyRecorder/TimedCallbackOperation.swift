import Foundation

struct TimedCallbackOperation {
  struct Timeout: Error, Equatable {}

  static func run(
    timeout: Duration,
    start: (@escaping @Sendable (Error?) -> Void) -> Void
  ) async throws {
    let gate = CompletionGate()

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        gate.register(continuation)
        start { error in
          gate.complete(error.map(Result.failure) ?? .success(()))
        }

        Task {
          try await Task.sleep(for: timeout)
          gate.complete(.failure(Timeout()))
        }
      }
    } onCancel: {
      gate.complete(.failure(CancellationError()))
    }
  }
}

private final class CompletionGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var result: Result<Void, Error>?

  func register(_ continuation: CheckedContinuation<Void, Error>) {
    lock.lock()

    if let result {
      lock.unlock()
      continuation.resume(with: result)
    } else {
      self.continuation = continuation
      lock.unlock()
    }
  }

  func complete(_ result: Result<Void, Error>) {
    lock.lock()

    guard self.result == nil else {
      lock.unlock()
      return
    }

    self.result = result
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }
}
