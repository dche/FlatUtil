import Foundation
import XCTest
@testable import FlatUtil

class ObservableCombiningTests: XCTestCase {

    func testCombineLatest() {
        let s1 = Observable.interval(0.2.seconds).map { $0 * 2 + 1 }
        let s2 = Observable.interval(0.2.seconds).delay(0.1.seconds).map { $0 * 2 }
        let o = s1.combine(latest: s2).take(5)
        expectResults(observable: o.map { $0.0 }, satisfy: {
            XCTAssertEqual($0, [1,3,3,5,5])
        })
        expectResults(observable: o.map { $0.1 }, satisfy: {
            XCTAssertEqual($0, [0,0,2,2,4])
        })
    }

    func testZipWithLatest() {
        let o = Observable.interval(0.1.seconds).map { $0 * 2 + 1 }.take(5)

        expectResults(observable: o.zipWith(latest: Observable<Int>.empty()).map { $0.0 }, satisfy: {
            XCTAssert($0.isEmpty)
        })

        let s = Observable.interval(0.2.seconds).delay(0.1.seconds).map { $0 * 2 }
        expectResults(observable: o.zipWith(latest: s).map { $0.0 }, satisfy: {
            XCTAssertEqual($0, [5,7,9])
        })
        expectResults(observable: o.zipWith(latest: s).map { $0.1 }, satisfy: {
            XCTAssertEqual($0, [0,0,2])
        })
    }

    func testMerge() {
        let s1 = Observable.interval(0.2.seconds).map { _ in "a" }
        let s2 = Observable.interval(0.2.seconds).delay(0.1.seconds).map { _ in "b" }
        let s3 = Observable<String>.empty()
        let o = Observable.merge(s1, s2, s3).take(5)

        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, ["a","b","a","b","a"])
        })
    }

    func testStartWith() {
        let o = Observable.from(sequence: [1,2,3])
        let s1 = Observable<Int>.empty()
        let s2 = Observable.from(sequence: [4,5,6,7])

        expectResults(observable: o.start(with: s1), satisfy: {
            XCTAssertEqual($0, [1,2,3])
        })
        expectResults(observable: s1.start(with: o), satisfy: {
            XCTAssertEqual($0, [1,2,3])
        })
        expectResults(observable: o.start(with: s2), satisfy: {
            XCTAssertEqual($0, [4,5,6,7,1,2,3])
        })
    }

    func testZip() {
        let o = Observable.interval(20.milliseconds).take(5)
        let s1 = Observable<Int>.empty()
        let s2 = Observable.range(start: 10, count: 3)

        // Again, tuple is not `Equatable`.
        expectResults(observable: o.zip(s1).map { $0.0 }, satisfy: {
            XCTAssert($0.isEmpty)
        })
        expectResults(observable: o.zip(s2).map { $0.0 }, satisfy: {
            XCTAssertEqual($0, [0,1,2])
        })
        expectResults(observable: o.zip(s2).map { $0.1 }, satisfy: {
            XCTAssertEqual($0, [10,11,12])
        })
    }

    func testSwitchLatest() {
        let s = Observable.interval(0.1.seconds)
        let s1 = s.map { $0 * 2 }   // The first one never completes.
        let s2 = s.map { $0 * 2 + 1 }.take(3)
        let os = [s1, s2]

        let o = Observable.interval(0.2.seconds).take(2).map { os[$0] }
        expectResults(observable: o.switchLatest(), satisfy: {
            XCTAssertEqual($0, [0,2,1,3,5])
        })
    }
}
