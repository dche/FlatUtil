
import Foundation
import XCTest
@testable import FlatUtil

class ObservableTransformingTests: XCTestCase {

    func testBuffer() {
        let o = Observable.from(sequence: [1,2,3,4,5,6,7])
            .buffer(count: 2)
            // [Int] is not Equatable.
            .map { $0.reduce(0, +) }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [3,7,11,7])
        })
    }

    func testFlatMap() {
        let o = Observable.range(start: 1, count: 2).flatMap {
            Observable.range(start: $0, count: 3)
        }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,2,3,2,3,4])
        })
    }

    func testFlatMapLatest() {
        let o = Observable.interval(0.2.seconds).take(3).flatMapLatest {_ in
            Observable.interval(120.milliseconds).take(4)
        }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [0,1,0,1,0,1,2,3])
        })
    }

    func testMap() {
        let o = Observable.from(sequence: [1,2,3])
        let omap = o.map { $0 + 1 }

        expectResults(observable: o) { XCTAssertEqual($0, [1, 2, 3]) }
        expectResults(observable: omap) { XCTAssertEqual($0, [2, 3, 4]) }
    }

    func testGroupBy() {
        let s = Observable.interval(0.2.seconds).take(6).group(by: { $0 % 2 })
        var o = s.element(at: 0).flatMap { $0 }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [0,2,4])
        })
        o = s.element(at: 1).flatMap { $0 }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,3,5])
        })
    }

    func testScan() {
        let o = Observable.range(start: 1, count: 3).scan(+)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,3,6])
        })
    }

    func testWindow() {
        let o = Observable.interval(0.2.seconds)
            .take(15)
            .windowWith(count: 5)
            .flatMap { $0.count() }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [5,5,5])
        })
    }

    func testZipWithIndex() {
        let o = Observable.from(sequence: [1,2,3]).zipWithIndex()
        // Tuple is not Equatable.
        let l = o.map { $0.0 }
        let r = o.map { $0.1 }

        expectResults(observable: l) {
            XCTAssertEqual($0, [1,2,3])
        }
        expectResults(observable: r) {
            XCTAssertEqual($0, [0,1,2])
        }
    }
}
