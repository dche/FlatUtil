//
// FlatUtil - Random.swift
//
// Random number generators and `Random` protocol.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

import Darwin

/// Random number generator.
public protocol Rng {

    ///
    mutating func fill(buffer: UnsafeMutableRawPointer, size: Int)

    /// Returns a random `UInt32` number.
    mutating func nextUInt32() -> UInt32

    /// Returns a random `UInt32` number than is less than or equal to `max`.
    mutating func nextUInt32(max: UInt32) -> UInt32

    /// Returns a random `UInt64` number.
    mutating func nextUInt64() -> UInt64

    /// Returns a random `UInt64` number than is less than or equal to `max`.
    mutating func nextUInt64(max: UInt64) -> UInt64

    /// Returns a random `Float` number in the interval [0, 1).
    mutating func nextFloat() -> Float

	/// Returns a random `Float` number in the interval [0, 1]
    // mutating func nextFloatClosed() -> Float

	/// Returns a random `Float` number in the interval (0, 1)
    // mutating func nextFloatOpen() -> Float

    /// Returns a random `Double` number in the interval [0, 1)
    mutating func nextDouble() -> Double

    /// Returns a random `Double` number in the interval [0, 1]
    // mutating func nextDoubleClosed() -> Double

    /// Returns a random `Double` number in the interval (0, 1)
    // mutating func nextDoubleOpen() -> Double
}

public protocol SeedableRng: Rng {

    associatedtype Seed

    /// Reseed `self` with the given `seed`.
    mutating func reseed(_ seed: Seed)

    init (seed: Seed)
}

extension Rng {

    // Default implementation based on `fill(buffer:size:)`.

    mutating public func nextUInt32() -> UInt32 {
        var bits: UInt32 = 0
        fill(buffer: &bits, size: MemoryLayout<UInt32>.stride)
        return bits
    }

    mutating public func nextUInt32(max: UInt32) -> UInt32 {
        return nextUInt32() % (max &+ 1)
    }

    mutating public func nextUInt64() -> UInt64 {
        return (UInt64(self.nextUInt32()) << 32) | UInt64(self.nextUInt32())
    }

    mutating public func nextUInt64(max: UInt64) -> UInt64 {
        return nextUInt64() % (max &+ 1)
    }

    private func normalize(_ i: UInt32) -> Float32 {
        let UPPER_MASK: UInt32 = 0x3F80_0000
        let LOWER_MASK: UInt32 = 0x007F_FFFF
        let tmp = UPPER_MASK | (i & LOWER_MASK)
        return unsafeBitCast(tmp, to: Float.self) - 1
    }

    private func normalize(_ i: UInt64) -> Double {
        let UPPER_MASK: UInt64 = 0x3FF0_0000_0000_0000
        let LOWER_MASK: UInt64 = 0x000F_FFFF_FFFF_FFFF
        let tmp = UPPER_MASK | (i & LOWER_MASK)
        return unsafeBitCast(tmp, to: Double.self) - 1
    }

    mutating public func nextFloat() -> Float {
        return normalize(self.nextUInt32())
    }

    // mutating public func nextFloatClosed() -> Float {
    //     fatalError()
    // }

    // mutating public func nextFloatOpen() -> Float {
    //     fatalError()
    // }

    mutating public func nextDouble() -> Double {
        return normalize(self.nextUInt64())
    }

    // mutating public func nextDoubleClosed() -> Double {
    //     fatalError()
    // }

    // mutating public func nextDoubleOpen() -> Double {
    //     fatalError()
    // }
}

public struct DevRandom: Rng {

	// Reference type for storing file descriptor.
	private final class Dev {
        let fd: Int32
        init () {
            self.fd = open("/dev/random", O_RDONLY)
        }
        deinit {
            guard fd >= 0 else { return }
            close(fd)
        }
	}

    private let dev: Dev

    public init () {
        self.dev = Dev()
    }

	mutating public func fill(buffer: UnsafeMutableRawPointer, size: Int) {
        let fd = self.dev.fd
        guard fd >= 0 else { return }
        read(fd, buffer, size)
	}
}


/// [Xoroshiro128+](http://xoroshiro.di.unimi.it) PRNG.
///
/// Directly translated from the public domain C implementation
/// by David Blackman and Sebastiano Vigna.
public struct Xoroshiro: SeedableRng {

	public typealias Seed = UInt64

	private var state: (UInt64, UInt64) = (0, 0)

	public init (seed: Seed) {
		self.reseed(seed)
	}

	public init () {
        var dr = DevRandom()
		self.init (seed: dr.nextUInt64())
	}

	public mutating func reseed(_ seed: Seed) {
		// SplixMix64
		var s = seed &+ 0x9E3779B97F4A7C15
		s = (s ^ (s >> 30)) ^ 0xBF58476D1CE4E5B9
		s = (s ^ (s >> 27)) ^ 0x94D049BB133111EB
		self.state = (seed, s ^ (s >> 31))
	}

	public mutating func nextUInt64() -> UInt64 {
		let result = state.0 &+ state.1
		let x = state.0 ^ state.1
		state.0 = ((state.0 << 55) | (state.0 >> 9)) ^ x ^ (x << 14)	// a, b
		state.1 = (x << 36) | (x >> 28)	// c
		return result
	}

	public mutating func fill(buffer: UnsafeMutableRawPointer, size: Int) {
        let u64_sz = MemoryLayout<UInt64>.stride
        let count = size / u64_sz
        let remain = size % u64_sz
        let buf = buffer.bindMemory(to: UInt64.self, capacity: count)
        for i in 0..<count {
            buf[i] = nextUInt64()
        }
        guard remain > 0 else { return }
        var rn = nextUInt64()
        let lbuf = buffer.bindMemory(to: UInt8.self, capacity: size)
        UnsafeMutablePointer<UInt64>(&rn).withMemoryRebound(to: UInt8.self, capacity: remain) { rbuf in
            for i in 0..<remain {
                lbuf[size - 1 - i] = rbuf[i]
            }
        }
	}
}

#if !os(Linux)

public struct Arc4Rng: Rng {

    public init () {}

	mutating public func fill(buffer: UnsafeMutableRawPointer, size: Int) {
		arc4random_buf(buffer, size)
	}

	mutating public func nextUInt32() -> UInt32 {
		return arc4random()
	}
}

#endif

/// Types that can be randomly constructed.
public protocol Random {

    /// Constructs a random instance using given `Rng`.
    init(withRng: inout Rng)
}

extension Random {

	/// Constructs a new random instance using default `Rng`.
    ///
	/// On Linux, a thread local, randomly seeded `Xoroshiro` is the default RNG.
	/// On Apple platforms, `Arc4Rng` is used.
    public static func random() -> Self {
#if os(Linux)
		// TODO: Use a thread-local stored `Xoroshiro`
#else
        var rng: Rng = Arc4Rng()
#endif
        return Self.init(withRng: &rng)
    }
}

extension UInt: Random {
	public init(withRng rng: inout Rng) {
        var i: UInt = 0
        withUnsafeMutablePointer(to: &i) { ptr in
            rng.fill(buffer: ptr, size: MemoryLayout<UInt>.stride)
        }
        self = i
    }
}

extension UInt32: Random {
    public init (withRng rng: inout Rng) {
        self = rng.nextUInt32()
    }
}

extension UInt64: Random {
	public init (withRng rng: inout Rng) {
		self = rng.nextUInt64()
	}
}

extension Int: Random {
    public init (withRng rng: inout Rng) {
        var i: Int = 0
        withUnsafeMutablePointer(to: &i) { ptr in
            rng.fill(buffer: ptr, size: MemoryLayout<Int>.stride)
        }
        self = i
    }
}

extension Int32: Random {
    public init (withRng rng: inout Rng) {
        let ui = rng.nextUInt32()
        let i = unsafeBitCast(ui, to: Int32.self)
        self = i
    }
}

extension Int64: Random {
	public init (withRng rng: inout Rng) {
        let ui = rng.nextUInt64()
        let i = unsafeBitCast(ui, to: Int64.self)
        self = i
    }
}

extension Float: Random {

	/// Constructs a random `Float` in the interval [0, 1).
    public init (withRng rng: inout Rng) {
        self = rng.nextFloat()
    }
}

extension Double: Random {

    /// Constructs a random `Double` in the interval [0, 1).
    public init (withRng rng: inout Rng) {
        self = rng.nextDouble()
    }
}
