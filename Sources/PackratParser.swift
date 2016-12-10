//
// FlatUtil - PackratParser.swift
//
// A Packrat parser combinator library.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

public struct ParsingExpression<T> {

    // Provided by combinators.
    fileprivate var match: (ParsingPosition) -> Result<ParsingState<T>>

    fileprivate init (_ match: @escaping (ParsingPosition) -> Result<ParsingState<T>>) {
        self.match = match
    }
}

// MARK: Combinators.

extension ParsingExpression {

    public static var empty: ParsingExpression {
        fatalError()
    }

    public static func terminal(
        regexp: Regexp
    ) -> ParsingExpression {
        // {
        //
        // }
        fatalError()
    }

    ///
    ///
    ///
    public static func nonterminal(
        _ name: String
    ) -> ParsingExpression {
        fatalError()
    }

    public static func optional(expression: ParsingExpression) -> ParsingExpression {
        fatalError()
    }

    public static func append<S>(expression: ParsingExpression<S>) -> ParsingExpression<[Any]> {
        fatalError()
    }

    public static func choice(expression: ParsingExpression) -> ParsingExpression {
        fatalError()
    }

    public static func repeatition(expression: ParsingExpression) -> ParsingExpression {
        fatalError()
    }

    public static func positiveRepeatition(expression: ParsingExpression) -> ParsingExpression {
        fatalError()
    }

    public func notFollowed(by: ParsingExpression) -> ParsingExpression {
        fatalError()
    }

    public func followed(by: ParsingExpression) -> ParsingExpression {
        fatalError()
    }
}

///
public struct ParsingGrammar {


    public func parse(text: String) {
        
    }
}
