import Foundation
import XCTest
@testable import FlatUtil

class ObservableUtilityTests: XCTestCase {

    func testDelay() {
        let o = Observable
            .from(sequence: [1,2,3])
            .delay(0.1.seconds)
            .timestamp()
            .map { $0.1 }
            .take(1)
        expectResults(observable: o) {
            print($0)
            XCTAssert($0[0] > 0.1.seconds)
        }
    }

    func testTapOn() {
        var sideEffect = 0
        let o = Observable.from(sequence: [1,2,3]).tap(on: { item in
            switch item {
            case let .item(i):
                return i == 2
            default:
                return false
            }
        }) {
            sideEffect = 2
        }
        expectResults(observable: o, satisfy: { ar in
            XCTAssertEqual(ar, [1,2,3])
            XCTAssertEqual(sideEffect, 2)
        })
    }

    func testInterval() {
        let o = Observable.interval(0.1.seconds).take(3).interval()
        expectResults(observable: o, satisfy: {
            XCTAssert($0[1] > 0.1.seconds)
        })
    }

    func testTimeout() {
        let o = Observable<Int>(callback: { o in
            o.onNext(0)
            o.onNext(1)
            usleep(100_000)
            o.onNext(2)
            usleep(300_000)
            o.onNext(3)
            o.onComplete()
        }).timeout(0.2.seconds)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [0,1,2])
        })
        expectError(observable: o, satisfy: { err in
            XCTAssertNotNil(err)
        })
    }

    func testTimestamp() {
        let o = Observable.interval(0.1.seconds).take(5).timestamp().map { $0.1 }
        expectResults(observable: o, satisfy: {
            XCTAssert($0[1] > $0[0] + 0.1.seconds)
        })
    }
}
