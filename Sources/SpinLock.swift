//
// FlatUtil - SpinLock.swift
//
// A simple wrapper of `OSSpinLockLock` functions.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

// TODO: Remove this file after `stdatomic` is available.

#if !os(Linux)

import Darwin

final class SpinLock {

    private var _lock: OSSpinLock = OSSpinLock()

    func lock() {
        withUnsafeMutablePointer(to: &_lock) { ptr in
            OSSpinLockLock(ptr)
        }
    }

    func unlock() {
        withUnsafeMutablePointer(to: &_lock) { ptr in
            OSSpinLockUnlock(ptr)
        }
    }
}

#else

import Dispatch

final class SpinLock {

    // Use `DispatchSemaphore` to simulate a R/W lock.
    private let _lock: DispatchSemaphore

    init() {
        self._lock = DispatchSemaphore(value: 1)
    }

    func lock() {
        let _ = self._lock.wait(timeout: DispatchTime.distantFuture)
    }

    func unlock() {
        self._lock.signal()
    }
}

#endif
