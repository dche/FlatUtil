//
// FlatUtil - Commandline.swift
//
// A simple utility for writing Command Line Interface.
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

import Foundation

// CHECK: Learn something from `clap.rs`' API.

fileprivate protocol CommandLineOption {
    // Long name of the option.
    var name: String { get }
    // Short name of the option. Can be empty.
    var shortName: String { get }
    // Description of the option.
    var description: String { get }
    // Returns `true` if the option's have have been set.
    var hasValue: Bool { get }
    // Sets the option's value.
    mutating func set(stringValue: String) throws
}

fileprivate struct FlagOption: CommandLineOption {
    let name: String
    let shortName: String
    let description: String
    var value: Bool
    var hasValue: Bool {
        return true
    }
    mutating func set(stringValue: String) {
        assert(stringValue.isEmpty)
        self.value = true
    }
}

fileprivate struct ValueOption<T>: CommandLineOption {
    let name: String
    let shortName: String
    let description: String
    var value: T?
    let validator: (String) throws -> T
    var hasValue: Bool {
        return value != nil
    }
    mutating func set(stringValue: String) throws {
        self.value = try validator(stringValue)
    }
}

public final class CommandLineParser {

    /// This structure contains all commandline options with correctly set
    /// option values.
    ///
    /// This structure is created after the command line is successfully
    /// parsed.
    public struct Options {

        private let options: [String:CommandLineOption]

        fileprivate init (options: [String:CommandLineOption]) {
            self.options = options
        }

        /// Returns `true` if there is no command line options defined.
        public var isEmpty: Bool { return options.isEmpty }

        /// Number of options.
        public var count: Int { return options.count }

        /// Returns `true` if there is a flag option with given `name`
        /// and its value is `true`.
        public func has(flag name: String) -> Bool {
            return options.contains {
                $1.name == name.lowercased() &&
                ($1 as? FlagOption)?.value ?? false
            }
        }

        /// Returns the value of a value option with name given by parameter
        /// `option`. Returns `nil` if there is no such option.
        public func valueOf<T>(option: String) -> T? {
            let o = options[option.lowercased()] as? ValueOption<T>
            return o?.value
        }
    }

    /// Error occured durign parsing command line options.
    ///
    /// Your option value validators can also throw this error.
    public enum ParsingError: Error {
        case cause(String)
    }

    private class Parser {

        // Option name is case insensible.
        static let longOptionNamePattern =
            Regexp(pattern: "^([a-z][a-z\\-]*[a-z])(=(.+))?$")!

        // Short name is case sensible.
        static let shortOptionNamePattern = Regexp(pattern: "^\\-([a-zA-Z]+)$")!

        // For extracting long option name and value.
        static let longOptionPattern =
            Regexp(pattern: "^\\-\\-(no\\-)?([a-z][a-z\\-]*[a-z])(=(.+))?$", options: .caseInsensitive)!

        var _options = [String:CommandLineOption]()

        // Add `o` to `_definitions`.
        //
        // Does nothing if
        // - duplicated short/long names exist,
        // - short/long name does not match naming pattern.
        func defineOption(_ o: CommandLineOption) throws {
            // options can not be replaced.
            guard !_options.contains(where: {
                $0.0 == o.name
            }) else {
                throw CommandLineParser.error("Program bug: Duplicated option name [\(o.name)].")
            }
            guard o.shortName.isEmpty || !_options.contains(where: {
                $0.1.shortName == o.shortName
            }) else {
                let c = "Program bug: Duplicated option short name [\(o.shortName)]."
                throw CommandLineParser.error(c)
            }
            guard o.name ~= Parser.longOptionNamePattern else {
                throw CommandLineParser.error("Program bug: Invalid option name [\(o.name)].")
            }
            guard o.shortName.isEmpty || ("-" + o.shortName) ~= Parser.shortOptionNamePattern else {
                throw CommandLineParser.error("Program bug: Invalid option short name [\(o.shortName)].")
            }
            _options[o.name] = o
        }

        func parse(commandline: ArraySlice<String>) -> Result<ArraySlice<String>> {
            let words = commandline

            func parseOptionAt(index: Int) -> Result<Int> {
                if index == words.count { return .value(index) }

                assert(index < words.count)

                let word = words[index + words.startIndex]
                let next = index + 1

                if word == "--" {
                    return .value(next)
                }
                if word.hasPrefix("--") {
                    return parse(long: word, next: next)
                }
                if word.hasPrefix("-") {
                    return parse(shorts: word, next: next)
                }
                return .value(index)
            }

            func optionWith(name: String) -> CommandLineOption? {
                return _options.filter { $0.value.name == name }.first?.value
            }

            func optionWith(shortName: String) -> CommandLineOption? {
                return _options.filter { $0.value.shortName == shortName }.first?.value
            }

            func parse(long str: String, next: Int) -> Result<Int> {
                guard let match = str.firstMatch(regexp: Parser.longOptionPattern) else {
                    return .error(CommandLineParser.error("Invalid command line option format: [\(str)]."))
                }

                let hasNo = !match[1].isEmpty
                let hasEqual = !match[3].isEmpty
                let optionName = match[2].lowercased()

                if hasEqual {
                    do {
                        guard var opt = optionWith(name: optionName) else {
                            return .error(CommandLineParser.error("Unkown option: [\(str)]."))
                        }
                        try opt.set(stringValue: match[4])
                        _options[optionName] = opt
                    } catch let ParsingError.cause(str) {
                        return .error(CommandLineParser.error(str))
                    } catch {
                        fatalError("Unreachable.")
                    }
                } else {
                    guard var opt = optionWith(name: optionName) as? FlagOption else {
                        return .error(CommandLineParser.error("Unknown flag option: [\(str)]."))
                    }
                    opt.value = !hasNo
                    _options[optionName] = opt
                }
                return parseOptionAt(index: next)
            }

            func parse(shorts str: String, next: Int) -> Result<Int> {
                var n = next
                guard let match = str.firstMatch(regexp: Parser.shortOptionNamePattern) else {
                    return .error(CommandLineParser.error("Invalid command line option format: [\(str)]."))
                }
                let chrs = match[1].characters
                // The last character is special. It could be a value option.
                for c in chrs.dropLast() {
                    guard var o = optionWith(shortName: String(c)) as? FlagOption else {
                        return .error(CommandLineParser.error("Unknown flag option short name: [\(c)]."))
                    }
                    o.value = true
                    _options[o.name] = o
                }
                let c = String(chrs.last!)
                guard var opt = optionWith(shortName: c) else {
                    return .error(CommandLineParser.error("Unknown option short name: [\(c)]."))
                }
                if opt is FlagOption {
                    try! opt.set(stringValue: "")
                } else {
                    do {
                        try opt.set(stringValue: words[n + words.startIndex])
                        n += 1
                    } catch let ParsingError.cause(str) {
                        return .error(CommandLineParser.error(str))
                    } catch {
                        fatalError("Unreachable.")
                    }
                }
                _options[opt.name] = opt
                return parseOptionAt(index: n)
            }

            // Constructs a list of value options that have `nil` value.
            func missingMandatoryOptions() -> [String] {
                return _options.filter { !$0.value.hasValue }.map { $0.value.name }
            }

            return parseOptionAt(index: 0).flatMap { rest in
                let mos = missingMandatoryOptions().joined(separator: ", ")
                guard mos.isEmpty else {
                    let reason = "Mandatory options are not specified: [\(mos)]."
                    return .error(CommandLineParser.error(reason))
                }
                return .value(words.suffix(from: rest + words.startIndex))
            }
        }
    }

    private static let commandNamePattern = Regexp(pattern: "^[a-z][a-z_\\-]+$")!

    /// Name of the command.
    ///
    /// Command name can only be lower cased.
    public let name: String

    /// Description of the command.
    public let description: String

    private var _subcommands = [String:CommandLineParser]()

    private let parser = Parser()

    /// Constructs a commandline program.
    public init (name: String = "", description: String) {
        self.name = name
        self.description = description
    }

    /// Constructs a `Commandline.ParsingError`.
    public static func error(_ cause: String) -> ParsingError {
        return ParsingError.cause(cause)
    }

    private static func printError(_ str: String) {
        FileHandle.standardError.write((str + "\n").data(using:String.Encoding.utf8)!)
    }

    /// Adds a sub-command to `self`.
    public func add(subCommand cmd: CommandLineParser) {
        let nm = cmd.name
        guard !_subcommands.contains(where: {
            $0.0 == nm
        }) else {
            CommandLineParser.printError("Program bug: Duplicated sub-command name.")
            return
        }
        guard nm ~= CommandLineParser.commandNamePattern else {
            CommandLineParser.printError("Program bug: Invalid sub-command name.")
            return
        }
        self._subcommands[nm] = cmd
    }

    /// Returns `true` if `self` has a sub-command with given name.
    public func has(subCommand name: String) -> Bool {
        return _subcommands.contains { $0.key == name }
    }

    private func define(option: CommandLineOption) {
        do {
            try parser.defineOption(option)
        } catch let ParsingError.cause(str) {
            // option definition error is bug of the program, and is not
            // reported in log.
            CommandLineParser.printError(str)
        } catch {
            fatalError("Unreachable.")
        }
    }

    /// Defines a flag option.
    public func define(
        flagOption name: String,
        shortName: String,
        description: String,
        defaultValue: Bool = false
    ) {
        let o =
            FlagOption(
                name: name.lowercased(),
                shortName: shortName,
                description: description,
                value: defaultValue)
        define(option: o)
    }

    // SWIFT EVOLUTION: Can't write a single initializer by setting
    //                  `defaultValue`'s type to `T?`.

    /// Defines a value option.
    public func define<T>(
        valueOption name: String,
        shortName: String,
        description: String,
        validator: @escaping (String) throws -> T
    ) {
        let o =
            ValueOption(name: name.lowercased(),
                        shortName: shortName,
                        description: description,
                        value: nil,
                        validator: validator)
        define(option: o)
    }

    /// Defines a value option with default value specified.
    public func define<T>(
        valueOption name: String,
        shortName: String,
        description: String,
        defaultValue: T,
        validator: @escaping (String) throws -> T
    ) {
        let o =
            ValueOption(name: name.lowercased(),
                        shortName: shortName,
                        description: description,
                        value: defaultValue,
                        validator: validator)
        define(option: o)
    }

    // /// Brief, one line usage message, derived from option definitions.
    // public var synopsis: String {
    //     return ""
    // }

    // /// Elaborate and formatted help message, derived from option definitions.
    // public func optionDescriptions(width: Int = 78, indent: Int = 4) -> String {
    //     return ""
    // }

    private func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        let lchrs = lhs.characters
        let rchrs = rhs.characters

        var diff = abs(lchrs.count - rchrs.count)
        var li = lchrs.startIndex
        var ri = rchrs.startIndex

        while (diff < 3 && li != lchrs.endIndex && ri != rchrs.endIndex) {
            if lchrs[li] != rchrs[ri] {
                diff += 1
            }
            li = lchrs.index(after: li)
            ri = rchrs.index(after: ri)
        }
        return diff < 3
    }

    /// Parses the command line arguments, returns the parse result if
    /// command names and options are valid.
    ///
    /// - parameter arguments: The command line arguments.
    /// - returns: `nil` if command names or options are invlid, other wise,
    /// returns a triple tuple that contains:
    ///   1. The sub-command path,
    ///   1. The parameters should be passd to the command,
    ///   1. An `Options` structure that contains all defined options.
    public func parse(arguments: [String]) -> ([String], [String], Options)? {
        let args = arguments.dropFirst()
        guard !args.isEmpty else {
            // Program name only.
            return ([], [], Options(options: parser._options))
        }
        let subcmd = args[args.startIndex]
        // No sub-command.
        if subcmd.hasPrefix("-") || _subcommands.isEmpty {
            switch self.parser.parse(commandline: args) {
            case let .value(params):
                let opts = Options(options: parser._options)
                return ([], [String](params), opts)
            case let .error(ParsingError.cause(str)):
                CommandLineParser.printError(str)
                return nil
            default:
                fatalError("Unreachable.")
            }
        }
        // Maybe a sub-command.
        if let cmd = _subcommands[subcmd] {
            guard let (subPath, params, opts) = cmd.parse(arguments: [String](args)) else {
                return nil
            }
            return ([cmd.name] + subPath, params, opts)
        }
        // Not a valid sub-command.
        CommandLineParser.printError("Unknown command: \"\(subcmd)\".")
        // Maybe a typo, print suggestions.
        let simcmds = _subcommands.keys.filter {
            self.isSimilar($0, subcmd)
        }
        if !simcmds.isEmpty {
            let initial = simcmds.dropLast()
            // SWIFT EVOLUTION: No `last` method of a weired collection type.
            var hint = simcmds.suffix(1).first!
            if !initial.isEmpty {
                hint = initial.joined(separator: ", ") + " or \(hint)"
            }
            print("Do you mean, \(hint)?")
        }
        return nil
    }
}
