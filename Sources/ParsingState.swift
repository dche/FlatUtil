//
// FlatUtil - ParsingState.swift
//
// Structure for storing parsing result and position.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

struct ParsingError: Error {
    let line: Int
    let column: Int
    let reason: String
}

struct ParsingPosition {
    let string: String.UTF8View
    let index: String.UTF8View.Index
    let line: Int
    let column: Int

    var character: UInt8 {
        return string[index]
    }

    func error<T>(message: String) -> Result<T> {
        let err =
            ParsingError(line: line, column: column, reason: message)
        return .error(err)
    }

    func newline() -> Result<ParsingPosition> {
        let idx = string.index(index, offsetBy: 1)
        guard idx < string.endIndex else {
            return self.error(message: "Unexpected end of input.")
        }
        let pos =
            ParsingPosition(string: string, index: idx, line: line + 1, column: 0)
        return .value(pos)
    }

    func advance() -> Result<ParsingPosition> {
        let idx = string.index(index, offsetBy: 1)
        guard idx < string.endIndex else {
            return self.error(message: "Unexpected end of input.")
        }
        let pos =
            ParsingPosition(string: string, index: idx, line: line, column: column + 1)
        return .value(pos)
    }
}

struct ParsingState<T> {
    let value: T
    let position: ParsingPosition

    init (_ value: T, _ position: ParsingPosition) {
        self.value = value
        self.position = position
    }
}
