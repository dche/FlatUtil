
import XCTest
@testable import FlatUtil

class CommandLineParserTests: XCTestCase {

    func testEmptyArgument() {
        let cmd = CommandLineParser(description: "")
        let pr = cmd.parse(arguments: [])
        XCTAssertNotNil(pr)
        let (cmds, params, opts) = pr!
        XCTAssert(cmds.isEmpty)
        XCTAssert(params.isEmpty)
        XCTAssert(opts.isEmpty)
    }

    func testCommandWithEmptyArgument() {
        let cmd = CommandLineParser(description: "")
        let (cmds, params, opts) = cmd.parse(arguments: ["prog", "help"])!
        XCTAssert(cmds.isEmpty)
        XCTAssertEqual(params.first!, "help")
        XCTAssert(opts.isEmpty)
    }

    func testShortFlagOption() {
        let cmd = CommandLineParser(description: "")
        cmd.define(flagOption: "verbose", shortName: "v", description: "Show more details.")
        cmd.define(flagOption: "useMagic", shortName: "m", description: "Set to use magic.")

        let (_, params, opts) = cmd.parse(arguments: ["prog", "-v", "/tmp/a.txt"])!
        XCTAssertEqual(params.count, 1)
        XCTAssertEqual(params.first!, "/tmp/a.txt")
        XCTAssertEqual(opts.count, 2)
        XCTAssert(opts.has(flag: "verbose"))
        XCTAssertFalse(opts.has(flag: "useMagic"))

        let (_, p1, o1) = cmd.parse(arguments: ["prog", "-m", "-v", "", ""])!
        XCTAssertEqual(p1.count, 2)
        XCTAssertEqual(p1.first!, "")
        XCTAssertEqual(o1.count, 2)
        XCTAssert(o1.has(flag: "useMagic"))
        XCTAssert(o1.has(flag: "verbose"))

        let (_, p2, o2) = cmd.parse(arguments: ["prog", "-vm"])!
        XCTAssertEqual(p2.count, 0)
        XCTAssertEqual(o2.count, 2)
        XCTAssert(o2.has(flag: "usemagic"))
        XCTAssert(o2.has(flag: "verbose"))
    }

    func testShortValueOption() {
        let cmd = CommandLineParser(description: "")
        let str_validator: (String) throws -> String = { str in
            return str
        }
        cmd.define(
            valueOption: "min-user-count",
            shortName: "i",
            description: "",
            defaultValue: "0",
            validator: str_validator)
        cmd.define(
            valueOption: "max-user-count",
            shortName: "a",
            description: "",
            defaultValue: "100",
            validator: str_validator)
        cmd.define(flagOption: "verbose", shortName: "v", description: "")

        let (_, p0, o0) = cmd.parse(arguments: [])!
        XCTAssert(p0.isEmpty)
        XCTAssertEqual(o0.count, 3)
        XCTAssertFalse(o0.has(flag: "verbose"))

        let (_, _, o1) = cmd.parse(arguments: ["prog", "-i", "20", "-va", "30"])!
        XCTAssertEqual(o1.count, 3)
        XCTAssert(o1.has(flag: "verbose"))
        let min_user_count: String? = o1.valueOf(option: "min-user-count")
        let max_user_count: String? = o1.valueOf(option: "max-user-count")
        XCTAssertNotNil(min_user_count)
        XCTAssertNotNil(max_user_count)
        XCTAssertEqual(min_user_count!, "20")
        XCTAssertEqual(max_user_count!, "30")
    }

    func testAllowEmptyShortName() {
        let cmd = CommandLineParser(description: "")
        cmd.define(flagOption: "npm", shortName: "", description: "install npm or not.")
        cmd.define(flagOption: "opencl", shortName: "", description: "")

        let (_, _, o) = cmd.parse(arguments: ["prog", "--no-npm", "--opencl", "rest"])!
        XCTAssertEqual(o.count, 2)
        XCTAssertFalse(o.has(flag: "npm"))
        XCTAssert(o.has(flag: "opencl"))
    }

    func testLongFlagOption() {
        let cmd = CommandLineParser(description: "")
        cmd.define(flagOption: "verbose", shortName: "v", description: "Show more details.")
        cmd.define(flagOption: "useMagic", shortName: "m", description: "Set to use magic.")

        let (_, _, o0) = cmd.parse(arguments: ["prog", "--useMagic"])!
        XCTAssertEqual(o0.count, 2)
        XCTAssertFalse(o0.has(flag: "verbose"))
        XCTAssert(o0.has(flag: "useMagic"))

        let (_, _, o1) = cmd.parse(arguments: ["prog", "--no-usemagic", "--verbose"])!
        XCTAssert(o1.has(flag: "verbose"))
        XCTAssert(!o1.has(flag: "usemagic"))
    }

    func testLongValueOption() {
        let cmd = CommandLineParser(description: "")
        let str_validator: (String) throws -> String = { str in
            return str
        }
        cmd.define(
            valueOption: "min-user-count",
            shortName: "i",
            description: "",
            defaultValue: "0",
            validator: str_validator)
        cmd.define(
            valueOption: "max-user-count",
            shortName: "a",
            description: "",
            defaultValue: "100",
            validator: str_validator)
        cmd.define(flagOption: "verbose", shortName: "v", description: "")

        let (_, _, o) = cmd.parse(arguments: ["prog", "--min-user-count=20"])!
        let i: String? = o.valueOf(option: "min-user-count")
        let a: String? = o.valueOf(option: "max-user-count")
        XCTAssertNotNil(i)
        XCTAssertNotNil(a)
        XCTAssertEqual(i!, "20")
        XCTAssertEqual(a!, "100")
    }

    func testDoubleHyphen() {
        let cmd = CommandLineParser(description: "")
        let (_, p, _) = cmd.parse(arguments: ["prog", "--", "--no-option", "a/b.txt"])!
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p[p.startIndex], "--no-option")
        XCTAssertEqual(p[p.startIndex + 1], "a/b.txt")
    }

    func testSubCommand() {
        let cmd = CommandLineParser(description: "")
        let subcmd = CommandLineParser(name: "version", description: "")
        subcmd.define(flagOption: "verbose", shortName: "v", description: "")

        cmd.add(subCommand: subcmd)
        XCTAssert(cmd.has(subCommand: "version"))

        let (cmds, _, o) = cmd.parse(arguments: ["prog", "version", "-v"])!
        XCTAssertEqual(cmds.count, 1)
        XCTAssertEqual(cmds[0], "version")
        XCTAssertEqual(o.count, 1)
        XCTAssert(o.has(flag: "verbose"))
    }

    func testInvalidSubCommandName() {
        let cmd = CommandLineParser(description: "")
        let subcmd = CommandLineParser(description: "")
        cmd.add(subCommand: subcmd)
        XCTAssertFalse(cmd.has(subCommand: ""))
    }

    func testDuplicatedOptionName() {
        let cmd = CommandLineParser(description: "")
        cmd.define(flagOption: "count", shortName: "c", description: "")
        cmd.define(valueOption: "count", shortName: "n", description: "") { cnt in
            return cnt
        }
        cmd.define(flagOption: "notcount", shortName: "c", description: "")

        let (_, _, o) = cmd.parse(arguments: ["prog", "--count"])!
        XCTAssertEqual(o.count, 1)
        XCTAssert(o.has(flag: "count"))

        XCTAssertNil(cmd.parse(arguments: ["prog", "-n", "2"]))
        XCTAssertNil(cmd.parse(arguments: ["prog", "--notcount"]))
    }

    func testMissingMandatoryOption() {
        let cmd = CommandLineParser(description: "")
        let str_validator: (String) throws -> String = { str in
            return str
        }
        cmd.define(
            valueOption: "min-user-count",
            shortName: "i",
            description: "",
            validator: str_validator)
        cmd.define(
            valueOption: "max-user-count",
            shortName: "a",
            description: "",
            defaultValue: "100",
            validator: str_validator)
        cmd.define(flagOption: "verbose", shortName: "v", description: "")

        XCTAssertNil(cmd.parse(arguments: ["prog", "-v"]))
        XCTAssertNil(cmd.parse(arguments: ["prog", "-v", "-a", "20"]))
        let pr = cmd.parse(arguments: ["prog", "-i", "10"])
        XCTAssertNotNil(pr)
        let (_, _, o) = pr!
        XCTAssertEqual(o.count, 3)
        let i: String = o.valueOf(option: "min-user-count")!
        XCTAssertEqual(i, "10")
    }

    func testInvalidOptionValue() {
        let name_validator: (String) throws -> String = { str in
            guard str.characters.count > 3 else {
                throw CommandLineParser.error("--name is too short.")
            }
            return str
        }
        let age_validator: (String) throws -> Int = { str in
            guard let i = Int(str), i > 10 else {
                throw CommandLineParser.error("--age is too young.")
            }
            return i
        }
        let cmd = CommandLineParser(description: "")
        cmd.define(valueOption: "name", shortName: "n", description: "Name.", validator: name_validator)
        cmd.define(valueOption: "age", shortName: "a", description: "Age.", validator: age_validator)

        XCTAssertNil(cmd.parse(arguments: ["prog", "--name=Ed", "-a", "20"]))
        XCTAssertNil(cmd.parse(arguments: ["prog", "--name=Edward", "-a", "-10"]))

        let (_, _, o) = cmd.parse(arguments: ["prog", "--name=Edward", "-a", "22"])!
        let nm: String? = o.valueOf(option: "name")
        let ag: Int? = o.valueOf(option: "age")
        XCTAssertEqual(nm!, "Edward")
        XCTAssertEqual(ag!, 22)
    }
}
