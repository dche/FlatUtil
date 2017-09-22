
import Foundation
import XCTest
@testable import FlatUtil

// Always subscribe on a serial queue in testing.
let emittingQueue = DispatchQueue(
    label: "com.eleuth.FlatUtilTests.ObservableTests.emittingQueue",
    qos: .background
)

extension EmittingResult {

    public func map<S>(_ operation: (T) throws -> S) -> EmittingResult<S> {
        switch self {
        case let .item(itm):
            do {
                let v = try operation(itm)
                return .item(v)
            } catch {
                return .error(error)
            }
        case .complete: return .complete
        case let .error(e): return .error(e)
        }
    }
}

struct ObservableTestError: Error {
    let reason: String

    static func == (lhs: ObservableTestError, rhs: ObservableTestError) -> Bool {
        return lhs.reason == rhs.reason
    }
}

class AllItems<T>: ObserverProtocol {

    typealias Item  = T

    private var _results: [T] = []
    private var _error: Error? = nil
    private var _expectation: (AllItems<T>) -> Void = { _ in }

    var results: [T] {
        return self._results
    }

    var error: Error? {
        return self._error
    }

    func onNext(_ item: T) {
        self._results.append(item)
    }

    func onComplete() {
        self._expectation(self)
    }

    func onError(_ err: Error) {
        self._error = err
        self._expectation(self)
    }

    func expect(_ op: @escaping (AllItems<T>) -> Void) {
        self._expectation = op
    }
}

extension XCTestCase {

    func expectResults<O: ObservableProtocol>(
        observable: O,
        satisfy: @escaping ([O.Item]) -> Void
    ) where O.Item: Equatable {
        let observer = AllItems<O.Item>()
        let e = expectation(description: "Results")
        observer.expect { rs in
            satisfy(rs.results)
            e.fulfill()
        }
        let _ = observable.subscribe(on: emittingQueue, observer: observer)
        waitForExpectations(timeout: 10)
    }

    func expectError<O: ObservableProtocol>(
        observable: O,
        satisfy: @escaping (Error?) -> Void
    ) {
        let observer = AllItems<O.Item>()
        let e = expectation(description: "Error")
        observer.expect { rs in
            satisfy(rs.error)
            e.fulfill()
        }
        let _ = observable.subscribe(on: emittingQueue, observer: observer)
        waitForExpectations(timeout: 10)
    }
}

class ObservableCreationTests: XCTestCase {

    func testGenerate() {
        let o = Observable.generate(first: 0, until: { $0 > 5 }, next: { $0 + 1 })
        expectResults(observable: o) {
            XCTAssertEqual($0, [0, 1, 2, 3, 4, 5])
        }
    }

    func testEmpty() {
        let o = Observable<Int>.empty()
        expectResults(observable: o) { XCTAssert($0.isEmpty) }
        expectError(observable: o) { XCTAssertNil($0) }
    }

    func testError() {
        let o = Observable<Int>.error(ObservableTestError(reason: "error"))
        expectResults(observable: o) { XCTAssert($0.isEmpty) }
        expectError(observable: o) { err in
            XCTAssertNotNil(err)
            XCTAssertEqual((err! as! ObservableTestError).reason, "error")
        }
    }

    func testFromSequence() {
        let o = Observable.from(sequence: [1,2,3])
        expectResults(observable: o) { XCTAssertEqual($0, [1, 2, 3]) }
    }

    func testInterval() {
        // NOTE: Small `ti` fails the test.
        let ti = 0.1.seconds
        weak var e = expectation(description: "wait")
        let o = Observable.interval(ti)
        let st = Time.now
        let _ = o.subscribe() {
            guard $0 < 8 else {
                // NOTE: The default dispatch queue subsribed on is
                // concurrent. `fulfill()` could be called more than once
                // o.w.
                e?.fulfill()
                e = nil
                return
            }
            let et = Time.now - st
            XCTAssert(et > ti * $0)
            XCTAssert(et < ti * ($0 + 1))
        }
        waitForExpectations(timeout: 1)
    }

    func testJust() {
        let o = Observable.just(3).take(5)
        expectResults(observable: o) { XCTAssertEqual($0, [3]) }
    }

    func testRange() {
        let o = Observable.range(start: 7, count: 3)
        expectResults(observable: o) { XCTAssertEqual($0, [7, 8, 9]) }
    }

    func testRepeat() {
        let o = Observable.repeat(7, count: 3)
        expectResults(observable: o) { XCTAssertEqual($0, [7, 7, 7]) }
    }

    func testStart() {
        var o = Observable.start(1)
        expectResults(observable: o) { XCTAssertEqual($0, [1]) }
        o = Observable<Int>.start({ 2 }())
        expectResults(observable: o) { XCTAssertEqual($0, [2]) }
    }

    func testTimer() {
        let e = expectation(description: "timeout")
        let o = Observable.timer("timer", after: 0.5.seconds)
        let st = Time.now
        let _ = o.subscribe() {(String) -> Void in
            XCTAssert(Time.now - st > 0.5.seconds)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
}
