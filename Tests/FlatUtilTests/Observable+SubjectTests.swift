
import Foundation
import XCTest
@testable import FlatUtil

class ObservableSubjectTests: XCTestCase {

    func testAsyncSubject() {

        var o = Observable.from(sequence: [1,2,3])
        var s = AsyncSubject<Int>()
        let _ = o.subscribe(observer: s)

        expectResults(observable: s) {
            XCTAssertEqual($0, [3])
        }
        expectResults(observable: s) {
            XCTAssertEqual($0, [3])
        }

        o = Observable<Int>.empty()
        s = AsyncSubject<Int>()
        let _ = o.subscribe(observer: s)
        expectResults(observable: s) {
            XCTAssertEqual($0, [])
        }

        o = Observable<Int>.error(ObservableTestError(reason: "error"))
        s = AsyncSubject<Int>()
        let _ = o.subscribe(observer: s)
        expectError(observable: s) { err in
            XCTAssertNotNil(err)
            XCTAssertEqual((err! as! ObservableTestError).reason, "error")
        }

        o = Observable<Int>(callback: { ob in
            ob.onNext(1)
            ob.onNext(2)
            ob.onError(ObservableTestError(reason: "interrupted"))
            ob.onNext(3)
            ob.onComplete()
        })
        s = AsyncSubject<Int>()
        let _ = o.subscribe(observer: s)
        expectError(observable: s) { err in
            XCTAssertNotNil(err)
            XCTAssertEqual((err! as! ObservableTestError).reason, "interrupted")
        }
    }

    func testBehaviorSubject() {
        var o = Observable.from(sequence: [1,2,3]).delay(0.2.seconds)
        var s = BehaviorSubject<Int>(initial: 0)

        var items: [Int] = []
        let e = expectation(description: "behavior")
        let _ = s.subscribe(on: emittingQueue, complete: {
            XCTAssertEqual(items, [0, 1, 2, 3])
            e.fulfill()
        }, next: {
            items.append($0)
        })
        let _ = o.subscribe(observer: s)
        waitForExpectations(timeout: 1)

        expectResults(observable: s) {
            XCTAssertEqual($0, [3])
        }

        o = Observable<Int>.empty()
        s = BehaviorSubject<Int>(initial: 0)
        let _ = o.subscribe(observer: s)
        expectResults(observable: s) {
            XCTAssertEqual($0, [0])
        }

        o = Observable<Int>(callback: { ob in
            ob.onNext(1)
            ob.onNext(2)
            ob.onError(ObservableTestError(reason: "interrupted"))
            ob.onNext(3)
            ob.onComplete()
        })
        s = BehaviorSubject<Int>(initial: 0)
        let _ = o.subscribe(on: emittingQueue, observer: s)
        expectError(observable: s) { err in
            XCTAssertNotNil(err)
            XCTAssertEqual((err! as! ObservableTestError).reason, "interrupted")
        }
    }

    func testPublishSubject() {
        let o = Observable.interval(0.1.seconds).delay(0.2.seconds).take(5)
        let s = PublishSubject<Int>()
        let _ = o.subscribe(observer: s)

        expectResults(observable: s) {
            XCTAssertEqual($0, [0, 1, 2, 3, 4])
        }
        expectResults(observable: s) {
            XCTAssert($0.isEmpty)
        }
    }

    func testReplaySubject() {
        let o = Observable.from(sequence: [0,1,2,3,4]).delay(0.2.seconds).take(5)
        let s = ReplaySubject<Int>(capacity: 3)
        let _ = o.subscribe(observer: s)

        expectResults(observable: s) {
            XCTAssertEqual($0, [0, 1, 2, 3, 4])
        }
        expectResults(observable: s) {
            XCTAssertEqual($0, [2, 3, 4])
        }
    }
}
