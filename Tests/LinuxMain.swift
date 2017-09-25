import XCTest
@testable import FlatUtilTests

extension ResultTests {
    static let allTests: [(String, (ResultTests) -> () throws -> ())] = [
        ("testValue", testValue),
        ("testError", testError),
        ("testMap", testMap),
        ("testFlatMap", testFlatMap),
        ("testOrElse", testOrElse),
    ]
}

extension FutureTests {
    static let allTests: [(String, (FutureTests) -> () throws -> ())] = [
        ("testNormalExecution", testNormalExecution),
        ("testLengthyOperation", testLengthyOperation),
        ("testErrorResult", testErrorResult),
        ("testMap", testMap),
        ("testAndThen", testAndThen),
        ("testFallback", testFallback),
        ("testJoin", testJoin),
        ("testPromise", testPromise),
        // ("testMulithreadAwait", testMulithreadAwait),
        ("testLongCompositionChain", testLongCompositionChain),
        ("testLongJoinChain", testLongJoinChain),
        ("testCustomDispatchQueue", testCustomDispatchQueue),
    ]
}

extension PromiseTests {
    static let allTests: [(String, (PromiseTests) -> () throws -> ())] = [
        ("testResolve", testResolve),
        ("testReject", testReject),
        ("testThen", testThen),
        ("testCatch", testCatch),
        ("testAwait", testAwait),
        ("testAll", testAll),
        ("testRace", testRace),
    ]
}

extension GenTests {
    static let allTests: [(String, (GenTests) -> () throws -> ())] = [
        ("testFilter", testFilter),
        ("testMap", testMap),
        ("testFlatMap", testFlatMap),
        ("testMakeIterator", testMakeIterator),
        ("testTwo", testTwo),
    ]
}

extension QuickCheckTests {
    static let allTests: [(String, (QuickCheckTests) -> () throws -> ())] = [
        ("testAllPrime", testAllPrime),
        ("testProperty", testProperty),
        ("testFailed", testFailed),
    ]
}

extension RegexpTests {
    static let allTests: [(String, (RegexpTests) -> () throws -> ())] = [
        ("testFirstMatch", testFirstMatch),
        ("testMatch", testMatch),
        ("testNotMatch", testNotMatch),
        ("testEmptyPattern", testEmptyPattern),
    ]
}

extension RngTests {
    static let allTests: [(String, (RngTests) -> () throws -> ())] = [
        ("testDevRandom", testDevRandom),
        ("testXoroshiro", testXoroshiro),
        ("testDefaultRng", testDefaultRng),
    ]
}

extension CommandLineParserTests {
    static let allTests: [(String, (CommandLineParserTests) -> () throws -> ())] = [
        ("testEmptyArgument", testEmptyArgument),
        ("testCommandWithEmptyArgument", testCommandWithEmptyArgument),
        ("testShortFlagOption", testShortFlagOption),
        ("testShortValueOption", testShortValueOption),
        ("testAllowEmptyShortName", testAllowEmptyShortName),
        ("testLongFlagOption", testLongFlagOption),
        ("testLongValueOption", testLongValueOption),
        ("testDoubleHyphen", testDoubleHyphen),
        ("testSubCommand", testSubCommand),
        ("testInvalidSubCommandName", testInvalidSubCommandName),
        ("testDuplicatedOptionName", testDuplicatedOptionName),
        ("testMissingMandatoryOption", testMissingMandatoryOption),
        ("testInvalidOptionValue", testInvalidOptionValue),
    ]
}

extension ObservableCreationTests {
    static let allTests: [(String, (ObservableCreationTests) -> () throws -> ())] = [
        ("testGenerate", testGenerate),
        ("testEmpty", testEmpty),
        ("testError", testError),
        ("testFromSequence", testFromSequence),
        ("testInterval", testInterval),
        ("testJust", testJust),
        ("testRange", testRange),
        ("testRepeat", testRepeat),
        ("testStart", testStart),
        ("testTimer", testTimer),
    ]
}

extension ObservableErorTests {
    static let allTests: [(String, (ObservableErorTests) -> () throws -> ())] = [
        ("testCatch", testCatch),
        ("testRetry", testRetry),
    ]
}

// TODO: Add more `Observable` test cases.

XCTMain([
    testCase(ResultTests.allTests),
    testCase(FutureTests.allTests),
    testCase(PromiseTests.allTests),
    testCase(GenTests.allTests),
    testCase(QuickCheckTests.allTests),
    testCase(RegexpTests.allTests),
    testCase(RngTests.allTests),
    testCase(CommandLineParserTests.allTests),
    testCase(ObservableCreationTests.allTests),
    testCase(ObservableErorTests.allTests),
])
