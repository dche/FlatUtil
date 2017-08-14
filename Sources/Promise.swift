//
// FlatUtil - Promise.swift
//
// A very simple Promise constuct based on Future.
//
// Copyright (c) 2017 The FlatUtil authors.
// Licensed under MIT License.

import Dispatch

/// An implementation of the popular Promise API. The implementation is
/// based on the `Future`, which is a concept equivalent to `Promise`.
///
/// - seealso: (Promise documentation on MDN)
///   [https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Global_Objects/Promise]
public struct Promise<T> {

    fileprivate let f: Future<T>

    /// Creates a `Promise` from a `Future`.
    public init(_ future: Future<T>) {
        self.f = future
    }

    /// Creates a `Promise` with an operation that computes a value.
    /// The computation is executed on given dispatch queue.
    ///
    /// - parameters:
    ///     - dispatchQueue: The dispatch queue where the value if computed.
    ///     - operation: The computation that returns the fulfilled value.
    public init(
        dispatchQueue q: DispatchQueue? = nil,
        operation o: @escaping () -> Result<T>
    ) {
        self.f = Future(dispatchQueue: q, operation: o)
    }

    /// Returns a `Promise` that is fulfilled with the given value.
    ///
    /// - parameters:
    ///     - val: The fulfilled value.
    public static func resolve(_ val: T) -> Promise<T> {
        return Promise(Future(value: val))
    }

    /// Returns a `Promise` that is rejected with the given reason.
    public static func reject(_ reason: Error) -> Promise<T> {
        return Promise(Future(error: reason))
    }

    /// Returns a `Promise` that is settled with a value that is derived
    /// from the fulfilled value of the receiver.
    public func then<S>(_ operation: @escaping (T) -> S) -> Promise<S> {
        return Promise<S>(self.f.map { Result.value(operation($0)) })
    }

    /// `FlatMap` version of `then`.
    public func then<S>(_ operation: @escaping (T) -> Promise<S>) -> Promise<S> {
        return Promise<S>(self.f.andThen { operation($0).f })
    }

    /// Returns a `Promise` that is settled with the fulfilled value of the
    /// receiver, or a value derived from the error
    public func fallback(_ handler: @escaping (Error) -> T?) -> Promise<T> {
        return Promise(self.f.fallback {
            // Called if only self.f's result IS an error.
            let err = self.f.result().error!
            guard let v = handler(err) else {
                return Future(error: err)
            }
            return Future(value: v)
        })
    }

    /// `FlatMap` version of `fallback`.
    public func fallback(_ handler: @escaping (Error) -> Promise<T>?) -> Promise<T> {
        return Promise(self.f.fallback {
            let err = self.f.result().error!
            guard let p = handler(err) else {
                return Future(error: err)
            }
            return p.f
        })
    }

    /// Blocks the caller and returns the fufilled value of the receiver.
    /// Returns `nil` if the receiver is rejected.
    public func await() -> T? {
        return self.f.result().value
    }
}

extension Promise {

    /// Returns a `Promise` that is fulfilled with an `Array` of fulfilled
    /// values of given promises.
    public static func all<S, T>(_ promises: S) -> Promise<[T]>
        where
        S: Sequence,
        S.Iterator.Element == Promise<T>
    {
        var res = Promise<[T]>.resolve([])
        guard promises.underestimatedCount > 0 else {
            return res
        }
        promises.forEach({ p in
            let future: Future<[T]> = res.f.join(p.f) { (ary, v) in
                var ar = ary
                ar.append(v)
                return Future(value: ar)
            }
            res = Promise<[T]>(future)
        })
        return res
    }

    /// Returns a `Promise` that is settled with the fulfilled value or
    /// rejection error of the first settled `Promise` of given sequence of 
    /// `Promise`s.
    ///
    /// - note: Settlements of `Promise`s can not be cancelled. So if
    /// a `Promise` has side effects, the effects will happen even if the
    /// `Promise` is not the first settled one.
    public static func race<S, T>(_ promises: S) -> Promise<T>
        where
        S: Sequence,
        S.Iterator.Element == Promise<T>
    {
        return Promise<T> {
            let lck = SpinLock()
            let rsc = DispatchSemaphore(value: 0)
            var val: Result<T>? = nil
            for p in promises {
                guard val == nil else { break }
                let _ = p.then {
                    Result<T>.value($0)
                }.fallback {
                    Result<T>.error($0)
                }.then { (v: Result<T>) -> Result<T> in
                    lck.lock()
                    defer { lck.unlock() }
                    if val == nil {
                        val = v
                        rsc.signal()
                    }
                    return v
                }
            }
            rsc.wait()
            return val!
        }
    }
}
