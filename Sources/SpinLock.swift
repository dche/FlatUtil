//
// FlatUtil - SpinLock.swift
//
// A simple wrapper of `OSSpinLockLock` functions.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

import Darwin

public final class SpinLock {

    private var _lock: OSSpinLock = OSSpinLock()

    public func lock() {
        withUnsafeMutablePointer(to: &_lock) { ptr in
            OSSpinLockLock(ptr)
        }
    }

    public func tryLock() -> Bool {
        return withUnsafeMutablePointer(to: &_lock) { ptr in
            return OSSpinLockTry(ptr)
        }
    }

    public func unlock() {
        withUnsafeMutablePointer(to: &_lock) { ptr in
            OSSpinLockUnlock(ptr)
        }
    }
}
