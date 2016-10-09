//
// FlatUtil - Result.swift
//
// A simple composable construction for storing result of computation.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

/// Result of certain computation.
public enum Result<T> {

    case value(T)
    case error(Error)

    /// The value result; returns `nil` if `self` is an error.
    public var value: T? {
        switch self {
        case let .value(v): return v
        default: return nil
        }
    }

    /// The error result; returns `nil` if `self` is a value.
    public var error: Error? {
        switch self {
        case let .error(e): return e
        default: return nil
        }
    }

    /// Wraps `computation`'s result with `Result`.
    public init (_ computation: () throws -> T) {
        do {
            self = try .value(computation())
        } catch {
            self = .error(error)
        }
    }

    /// If `self` is a value, feeds the value to operation `op`, and then
    /// returns its result.
    public func flatMap<S>(_ op: (T) -> Result<S>) -> Result<S> {
        switch self {
        case let .error(e): return .error(e)
        case let .value(v): return op(v)
        }
    }

    /// If `self` is an error, executes operation `op`, and returns its
    /// result; returns `self` otherwise.
    public func orElse(_ op: () -> Result<T>) -> Result<T> {
        switch self {
        case .error(_): return op()
        default: return self
        }
    }

    /// Applies an operation `op` to the value of `self`, and then returns
    /// a new `Result` that contains the operation's return value.
    public func map<S>(_ op: (T) -> S) -> Result<S> {
        switch self {
        case let .error(e): return .error(e)
        case let .value(v): return .value(op(v))
        }
    }

    /// If `self` is a value, applies a failable operation to `self`'s value,
    /// and then returns the result of the operation; Returns `self`'s error
    /// otherwise.
    public func map<S>(_ op: (T) throws -> S) -> Result<S> {
        return self.flatMap { v in
            do {
                let s = try op(v)
                return .value(s)
            } catch {
                return .error(error)
            }
        }
    }
}
