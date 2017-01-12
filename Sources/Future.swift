//
// FlatUtil - Future.swift
//
// A simple composable construction for executing a computation asynchrously.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

import Foundation

#if os(Linux)
    import Dispatch
#endif

// SWIFT EVOLUTION: It's ideal to make `FutureExecutionError` a subtype of
//                  `Future`. Can not do this because `Future` is generic.

public enum FutureExecutionError: Error {
    case timeoutError
}

public final class Future<T> {

    private var _result: Result<T>?

    private var _exec: DispatchQueue?

    private var _semaphore: DispatchSemaphore?

    private var _lock: SpinLock?

    private var _completions: [(Result<T>) -> Void] = []

    private func complete(withResult r: Result<T>) {
        assert(_result == nil)
        // The only place where `_result` is set.
        self._result = r

        let lk = _lock!
        lk.lock()
        self._semaphore?.signal()
        self._semaphore = nil
        // Schedule dependants.
        if !_completions.isEmpty {
            let executor = _exec ?? DispatchQueue.global(qos: .background)
            for op in _completions {
                executor.async { op(r) }
            }
            _completions = []
        }
        _lock = nil
        _exec = nil
        lk.unlock()
    }

    private func onComplete(_ op: @escaping (Result<T>) -> Void) {
        _lock?.lock()
        defer { _lock?.unlock() }

        let r = _result
        guard r == nil else {
            // NOTE: `exec` might has been set to `nil`.
            let executor = _exec ?? DispatchQueue.global(qos: .background)
            executor.async { op(r!) }
            return
        }
        _completions.append(op)
    }

    // Constructs a `Future` that does not start its computation itself.
    // Instead, it asks the `Future`s on which it depends to do this for it.
    private init (dispatchQueue: DispatchQueue? = nil) {
        self._exec = dispatchQueue
        self._lock = SpinLock()
    }

    // Intializes and then submits `operation` to `dispatchQueue`.
    fileprivate init (
        dispatchQueue: DispatchQueue? = nil,
        operation: @escaping () -> Result<T>
    ) {
        self._exec = dispatchQueue
        self._lock = SpinLock()
        // TODO: Options to use other `qos`.
        let executor = dispatchQueue ?? DispatchQueue.global(qos: .background)
        executor.async {
            self.complete(withResult: operation())
        }
    }

    /// Constructs a `Future` object with an `operation` that returns a normal
    /// value.
    ///
    /// This initializer wraps the value to a `Result` structure.
    public convenience init (
        dispatchQueue: DispatchQueue? = nil,
        operation: @escaping () -> T
    ) {
        let op: () -> Result<T> = {
            return .value(operation())
        }
        self.init(dispatchQueue: dispatchQueue, operation: op)
    }

    /// Constructs a `Future` object with an `operation` that might throw
    /// exceptions.
    ///
    /// If exceptions do occur, they're captured in an error `Result` of the
    /// `Future`.
    public convenience init (
        dispatchQueue: DispatchQueue? = nil,
        operation: @escaping () throws -> T
    ) {
        let op: () -> Result<T> = {
            do {
                return try .value(operation())
            } catch {
                return .error(error)
            }
        }
        self.init(dispatchQueue: dispatchQueue, operation: op)
    }

    // Lifts a `Result` to a `Future`.
    private init (result: Result<T>) {
        self._result = result
    }

    /// Constructs a `Future` object with known value.
    public convenience init (value: T) {
        self.init(result: .value(value))
    }

    /// Constructs a `Future` object with known result that is a an error.
    public convenience init (error: Error) {
        self.init(result: .error(error))
    }

    /// Returns the computation result of `self`.
    ///
    /// This method will block the caller if the result is not ready yet.
    public func result(timeout: TimeInterval = TimeInterval.infinity) -> Result<T> {
        guard _result == nil else { return _result! }

        var sem = _semaphore
        if sem == nil {
            _lock?.lock()
            defer { _lock?.unlock() }

            if _result != nil { return _result! }
            if _semaphore == nil {
                _semaphore = DispatchSemaphore(value: 0)
            }
            sem = _semaphore
        }

        let dt = timeout.isInfinite ?
            DispatchTime.distantFuture :
            DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + UInt64(timeout.nanoseconds))
        assert(sem != nil)
        if sem!.wait(timeout: dt) == DispatchTimeoutResult.timedOut {
            return .error(FutureExecutionError.timeoutError)
        } else {
            sem!.signal()
        }
        assert(_result != nil)
        return _result!
    }

    /// Returns `true` if the computation of `self` has already been completed
    /// with a result.
    public var isCompleted: Bool { return _result != nil }

    public func map<S>(operation: @escaping (T) -> Result<S>) -> Future<S> {
        guard let res = _result else {
            let f = Future<S>(dispatchQueue: self._exec)
            self.onComplete {
                f.complete(withResult: $0.flatMap(operation))
            }
            return f
        }
        switch res {
        case let .value(val):
            return Future<S>(dispatchQueue: self._exec) {
                return operation(val)
            }
        case let .error(err):
            return Future<S>(result: .error(err))
        }
    }

    public func map<S>(operation: @escaping (T) -> S) -> Future<S> {
        return self.map { .value(operation($0)) }
    }

    public func andThen<S>(operation: @escaping (T) -> Future<S>) -> Future<S> {
        // TODO: `operation` is NOT a good name. Same in `map` and `fallback`.
        guard let res = _result else {
            let f = Future<S>(dispatchQueue: self._exec)
            self.onComplete {
                switch $0 {
                case let .error(err):
                    f.complete(withResult: .error(err))
                case let .value(val):
                    operation(val).onComplete {
                        f.complete(withResult: $0)
                    }
                }
            }
            return f
        }
        switch res {
        case let .value(val):
            return operation(val)
        case let .error(err):
            return Future<S>(error: err)
        }
    }

    public func fallback(operation: @escaping () -> Future<T>) -> Future<T> {
        guard let r = _result else {
            let f = Future<T>(dispatchQueue: self._exec)
            self.onComplete {
                switch $0 {
                case .error:
                    operation().onComplete {
                        f.complete(withResult: $0)
                    }
                case .value:
                    f.complete(withResult: $0)
                }
            }
            return f
        }
        switch r {
        case .error:
            return operation()
        default:
            return self
        }
    }

    public func join<R, S>(
        _ that: Future<R>,
        operation: @escaping (T, R) -> Future<(S)>
    ) -> Future<S> {
        guard let lr = _result, let rr = that._result else {
            let f = Future<S>(dispatchQueue: self._exec)
            if _result == nil {
                self.onComplete { lr in
                    switch (lr, that._result) {
                    // `self` is error.
                    case let (.error(err), _):
                        f.complete(withResult: .error(err))
                    // `that` is not ready.
                    case (_, nil):
                        return
                    // `that` is error.
                    case let (_, .error(err)?):
                        f.complete(withResult: .error(err))
                    // All's well.
                    case let (.value(lv), .value(rv)?):
                        operation(lv, rv).onComplete {
                            f.complete(withResult: $0)
                        }
                    default: break
                    }
                }
            }
            if that._result == nil {
                that.onComplete { rr in
                    switch (self._result, rr) {
                    case let (_, .error(err)):
                        f.complete(withResult: .error(err))
                    case (nil, _):
                        return
                    case let (.error(err)?, _):
                        f.complete(withResult: .error(err))
                    case let (.value(lv)?, .value(rv)):
                        operation(lv, rv).onComplete {
                            f.complete(withResult: $0)
                        }
                    default: break
                    }
                }
            }
            return f
        }
        let pr = lr.flatMap { lv in return rr.map { (lv, $0) } }
        switch pr {
        case let .value(pair):
            return operation(pair.0, pair.1)
        case let .error(err):
            return Future<S>(error: err)
        }
    }
}
