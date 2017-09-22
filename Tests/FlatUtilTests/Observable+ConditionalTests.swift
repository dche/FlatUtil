
import Foundation
import XCTest
@testable import FlatUtil

class ObservableConditionalTests: XCTestCase {

    func testAll() {
        var o = Observable.from(sequence: [1,2,3])
        expectResults(observable: o.all({ $0 > 0 }), satisfy: {
            XCTAssertEqual($0, [true])
        })
        expectResults(observable: o.all({ $0 < 3 }), satisfy: {
            XCTAssertEqual($0, [false])
        })

        o = Observable<Int>.empty()
        expectResults(observable: o.all({ $0 > 0 }), satisfy: {
            XCTAssert($0.isEmpty)
        })
    }

    func testAmb() {
        let s1 = Observable.from(sequence: [1,2,3]).delay(0.1.seconds)
        let s2 = Observable.interval(0.2.seconds).take(3).map { $0 + 4 }
        let o = Observable<Int>.amb(s1, s2)
        expectResults(observable: o) {
            // s2
            XCTAssertEqual($0, [4,5,6])
        }
    }

    func testDefaultItem() {
        var o = Observable<Int>.empty()
        expectResults(observable: o.defaultItem(2), satisfy: {
            XCTAssertEqual($0, [2])
        })

        o = Observable.from(sequence: [1,2,3])
        expectResults(observable: o.defaultItem(0), satisfy: {
            XCTAssertEqual($0, [1,2,3])
        })
    }

    func testContains() {
        var o = Observable.from(sequence: [1,2,3])
        expectResults(observable: o.contains(2), satisfy: {
            XCTAssertEqual($0, [true])
        })
        expectResults(observable: o.contains(0), satisfy: {
            XCTAssertEqual($0, [false])
        })
        o = Observable<Int>.empty()
        expectResults(observable: o.contains(2), satisfy: {
            XCTAssertEqual($0, [false])
        })
    }

    func testSequenceEqual() {
        let o = Observable.interval(0.1.seconds).take(5)
        let s1 = o.delay(0.2.seconds)
        let s2 = Observable.from(sequence: [0,1,2,3,4,5,6])
        let s3 = Observable<Int>.empty()
        let s4 = Observable.from(sequence: [0,2,3])
        let s5 = Observable.interval(150.milliseconds).take(5)
        let s6 = Observable<Int>(callback: { o in
            o.onNext(0)
            o.onError(ObservableTestError.init(reason: "noitem"))
        })

        expectResults(observable: o.sequenceEqual(s1)) {
            XCTAssertEqual($0, [true])
        }
        expectResults(observable: o.sequenceEqual(s2)) {
            XCTAssertEqual($0, [false])
        }
        expectResults(observable: o.sequenceEqual(s3)) {
            XCTAssertEqual($0, [false])
        }
        expectResults(observable: o.sequenceEqual(s4)) {
            XCTAssertEqual($0, [false])
        }
        expectResults(observable: o.sequenceEqual(s5)) {
            XCTAssertEqual($0, [true])
        }
        expectResults(observable: o.sequenceEqual(s6), satisfy: {
            XCTAssert($0.isEmpty)
        })
        expectError(observable: o.sequenceEqual(s6), satisfy: { e in
            XCTAssertEqual((e! as! ObservableTestError).reason, "noitem")
        })
    }
}
