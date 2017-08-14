import Foundation
import XCTest
@testable import FlatUtil

class ObservableFilteringTests: XCTestCase {

    func testDebounce() {
        let o = Observable<Int>(callback: { o in
            o.onNext(0)
            o.onNext(1)
            o.onNext(2)
            usleep(100_000)
            o.onNext(3)
            o.onNext(4)
            o.onComplete()
        }).debounce(0.1.seconds)
        expectResults(observable: o) {
            XCTAssertEqual($0, [0,3])
        }
    }

    func testElementAt() {
        let o = Observable.from(sequence: [1, 2, 3]).element(at: 1)
        expectResults(observable: o) {
            XCTAssertEqual($0, [2])
        }
    }

    func testFilter() {
        let o = Observable.from(sequence: [0,1,2,3]).filter {
            $0 % 2 == 0
        }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [0,2])
        })
    }

    func testFirst() {
        var o = Observable.from(sequence: [1,2,3]).first()
        expectResults(observable: o) {
            XCTAssertEqual($0, [1])
        }

        o = Observable<Int>.empty()
        expectResults(observable: o) {
            XCTAssert($0.isEmpty)
        }

        o = Observable.from(sequence: [1,2,3]).first { $0 > 1 }
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [2])
        })
    }

    func testIgnore() {
        var o = Observable.from(sequence: [1,2,3]).ignore()
        expectResults(observable: o, satisfy: {
            XCTAssert($0.isEmpty)
        })

        o = Observable<Int>(callback: { o in
            o.onNext(1)
            o.onError(ObservableTestError(reason: "ignore"))
        })
        expectError(observable: o) { err in
            XCTAssertNotNil(err)
            XCTAssertEqual((err! as! ObservableTestError).reason, "ignore")
        }
    }

    func testLast() {
        var o = Observable.from(sequence: [1,2,3]).last()
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [3])
        })

        o = Observable<Int>.empty()
        expectResults(observable: o, satisfy: {
            XCTAssert($0.isEmpty)
        })
    }

    func testSample() {
        let s0 = Observable.interval(0.1.seconds)
        let s1 = Observable.interval(0.2.seconds).delay(0.05.seconds).take(5)
        let o = s0.sample(s1)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,3,5,7,9])
        })
    }

    func testSampleInterval() {
        let o = Observable.interval(0.1.seconds).sample(interval: 0.24.seconds).take(3)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [0,2,4])
        })
    }

    func testSkip() {
        let o = Observable.from(sequence: [1,2,3,4,5])
        expectResults(observable: o.skip(2), satisfy: {
            XCTAssertEqual($0, [3,4,5])
        })
        expectResults(observable: o.skip(0), satisfy: {
            XCTAssertEqual($0, [1,2,3,4,5])
        })
        expectResults(observable: o.skip(10), satisfy: {
            XCTAssertEqual($0, [])
        })
    }

    func testSkipWhile() {
        let o = Observable.from(sequence: [1,1,2,1,1,2]).skip(while: { $0 < 2 })
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [2,1,1,2])
        })
    }

    func testSkipUntil() {
        let s = Observable<Int>.just(1).delay(0.1.seconds)
        let o = Observable<Int>.interval(0.1.seconds).skip(until: s).take(2)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [2,3])
        })
    }

    func testSkipLast() {
        let o = Observable.from(sequence: [1,2,3,4,5]).skip(last: 2)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,2,3])
        })
    }

    func testTake() {
        let s = Observable.from(sequence: [1,2,3])
        var o = s.take(3)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,2,3])
        })

        o = s.take(0)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [])
        })

        o = s.take(4)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,2,3])
        })

        o = Observable<Int>.empty().take(100)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [])
        })
    }

    func testTakeWhile() {
        let o = Observable.from(sequence: [1,2,3,4,5]).take(while: {
            $0 < 4
        })
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [1,2,3])
        })
    }

    func testTakeUntil() {
        let s = Observable<Int>.just(1).delay(0.2.seconds)
        let o = Observable<Int>.interval(0.1.seconds).take(until: s).take(3)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [0,1,2])
        })
    }

    func testTakeLast() {
        let o = Observable.from(sequence: [1,2,3,4,5]).take(last: 2)
        expectResults(observable: o, satisfy: {
            XCTAssertEqual($0, [4,5])
        })
    }

    func testThrottle() {
        let o = Observable.interval(0.1.seconds).throttle(0.2.seconds)
        expectResults(observable: o.take(3), satisfy: {
            XCTAssertEqual($0, [0,2,4])
        })
    }

    func testDistinct() {
        let o = Observable.from(sequence: [1,2,3,3,2,2,1]).distinct()
        expectResults(observable: o) {
            XCTAssertEqual($0, [1,2,3,2,1])
        }
    }

    func testUniq() {
        let o = Observable.from(sequence: [1,2,3,3,2,2,1]).uniq()
        expectResults(observable: o) {
            XCTAssertEqual($0, [1,2,3])
        }
    }
}
