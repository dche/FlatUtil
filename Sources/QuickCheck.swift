//
//  FlatUtil - QuickCheck.swift
//
//  A simple and incomplete implementation of `QuickCheck`.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

public struct GenIterator<T>: Sequence, IteratorProtocol {

    private var _rng: Rng

    private var _size: Int

    private let gen: (inout Rng) -> T

    fileprivate init (size: Int, gen: @escaping (inout Rng) -> T) {
        self._rng = Xoroshiro()
        self._size = size
        self.gen = gen
    }

    public mutating func next() -> T? {
        guard _size > 0 else { return nil }
        _size -= 1
        return gen(&_rng)
    }
}

public struct Gen<T> {

    fileprivate let gen: (inout Rng) -> T

    public init (gen: @escaping (inout Rng) -> T) {
        self.gen = gen
    }

    public func makeIterator(size: Int) -> GenIterator<T> {
        return GenIterator(size: size, gen: self.gen)
    }

    public func filter(_ p: @escaping (T) -> Bool) -> Gen<T> {
        return Gen { rng in
            var v = self.gen(&rng)
            while !p(v) {
                v = self.gen(&rng)
            }
            return v
        }
    }

    public func map<S>(_ fn: @escaping (T) -> S) -> Gen<S> {
        return Gen<S> { rng in
            return fn(self.gen(&rng))
        }
    }

    public func flatMap<S>(_ fn: @escaping (T) -> Gen<S>) -> Gen<S> {
        var vr: Rng = Xoroshiro()
        return Gen<S> { rng in
            return fn(self.gen(&rng)).gen(&vr)
        }
    }

    public func two() -> Gen<(T, T)> {
        return Gen<(T, T)> { rng in
            return (self.gen(&rng), self.gen(&rng))
        }
    }
}

extension Gen where T: Random {

    public init () {
        self.gen = { T.init(withRng: &$0) }
    }
}

extension Collection where Self: RandomAccessCollection, Self.IndexDistance == Int {

    public func gen() -> Gen<Self.Iterator.Element> {
        precondition(!self.isEmpty)
        return Gen { rng in
            let i = Int(rng.nextUInt32()) % self.count
            let idx = self.index(self.startIndex, offsetBy: i)
            return self[idx]
        }
    }

    // TODO: func gen (frequency: [Int]) -> Gen<> {}
}

public struct Property<T> {

    public let name: String

    /// The predication that is testable.
    private let spec: (T) throws -> Bool

    public init (_ name: String, spec: @escaping (T) throws -> Bool) {
        self.name = name
        self.spec = spec
    }

    fileprivate static func report(_ result: Result<Bool>, samples: [T]) {
        guard !samples.isEmpty else {
            print("Sample size is 0. No test run.")
            return
        }
        switch result {
        case .value(true):
            print("OK, passed \(samples.count) tests.")
        case .value(false):
            debugPrint("Failed, Falsifiable after \(samples.count) tests.")
            debugPrint(samples.last!)
        case let .error(err):
            debugPrint("Error occured at \(samples.count) tests.")
            debugPrint(err)
            debugPrint(samples.last!)
        }
    }

    public func check(_ gen: Gen<T>, size: Int) -> Bool {
        var rng: Rng = Xoroshiro()
        var samples = [T]()
        var result = Result.value(true)
        for _ in 0..<size {
            let x = gen.gen(&rng)
            samples.append(x)
            do {
                guard try spec(x) else {
                    result = .value(false)
                    break
                }
            } catch {
                result = .error(error)
                break
            }
        }
        Property<T>.report(result, samples: samples)
        // TODO: Labeling and classifying.
        return result.value ?? false
    }
}

public func quickCheck<T>(_ a: Gen<T>, size: Int, spec: (T) throws -> Bool) -> Bool {
    var rng: Rng = Xoroshiro()
    var samples = [T]()
    var result = Result.value(true)
    for _ in 0..<size {
        let x = a.gen(&rng)
        samples.append(x)
        do {
            guard try spec(x) else {
                result = .value(false)
                break
            }
        } catch {
            result = .error(error)
            break
        }
    }
    Property<T>.report(result, samples: samples)
    return result.value ?? false
}

public func quickCheck<S, T>(
    _ a: Gen<S>,
    _ b: Gen<T>,
    size: Int,
    spec: @escaping (S, T) throws -> Bool
) -> Bool {
    var xrng: Rng = Xoroshiro()
    var yrng: Rng = Xoroshiro()
    var samples = [(S, T)]()
    var result = Result.value(true)
    for _ in 0..<size {
        let (x, y) = (a.gen(&xrng), b.gen(&yrng))
        samples.append((x, y))
        do {
            guard try spec(x, y) else {
                result = .value(false)
                break
            }
        } catch {
            result = .error(error)
            break
        }
    }
    Property<(S, T)>.report(result, samples: samples)
    return result.value ?? false
}

public func quickCheck<S, T, U>(
    _ a: Gen<S>,
    _ b: Gen<T>,
    _ c: Gen<U>,
    size: Int,
    spec: @escaping (S, T, U) throws -> Bool
) -> Bool {
    var xrng: Rng = Xoroshiro()
    var yrng: Rng = Xoroshiro()
    var zrng: Rng = Xoroshiro()
    var samples = [(S, T, U)]()
    var result = Result.value(true)
    for _ in 0..<size {
        let (x, y, z) = (a.gen(&xrng), b.gen(&yrng), c.gen(&zrng))
        samples.append((x, y, z))
        do {
            guard try spec(x, y, z) else {
                result = .value(false)
                break
            }
        } catch {
            result = .error(error)
            break
        }
    }
    Property<(S, T, U)>.report(result, samples: samples)
    return result.value ?? false
}

public func quickCheck<S, T, U, V>(
    _ a: Gen<S>,
    _ b: Gen<T>,
    _ c: Gen<U>,
    _ d: Gen<V>,
    size: Int,
    spec: @escaping (S, T, U, V) throws -> Bool
) -> Bool {
    var xrng: Rng = Xoroshiro()
    var yrng: Rng = Xoroshiro()
    var zrng: Rng = Xoroshiro()
    var wrng: Rng = Xoroshiro()
    var samples = [(S, T, U, V)]()
    var result = Result.value(true)
    for _ in 0..<size {
        let (x, y, z, w) = (a.gen(&xrng), b.gen(&yrng), c.gen(&zrng), d.gen(&wrng))
        samples.append((x, y, z, w))
        do {
            guard try spec(x, y, z, w) else {
                result = .value(false)
                break
            }
        } catch {
            result = .error(error)
        }
    }
    Property<(S, T, U, V)>.report(result, samples: samples)
    return result.value ?? false
}
