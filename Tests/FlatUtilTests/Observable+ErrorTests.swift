

import Foundation
import XCTest
@testable import FlatUtil

class ObservableErorTests: XCTestCase {

    func testCatch() {
        let o = Observable<Int>(callback: { o in
            o.onNext(0)
            o.onNext(1)
            o.onError(ObservableTestError(reason: "recovered"))
            o.onNext(10)
            o.onNext(11)
        })
        let s = Observable.from(sequence: [2,3,4])
        expectResults(observable: o.catch { _ in s }) {
            XCTAssertEqual($0, [0,1,2,3,4])
        }
    }

    func testRetry() {
        let o = Observable<Int>(callback: { o in
            o.onNext(0)
            o.onNext(1)
            o.onError(ObservableTestError(reason: "1"))
            o.onNext(2)
            o.onError(ObservableTestError(reason: "2"))
            o.onNext(3)
            o.onComplete()
        })
        expectResults(observable: o.retry(count: 1), satisfy: {
            XCTAssertEqual($0, [0,1,2])
        })
        expectError(observable: o.retry(count: 1), satisfy: { err in
            XCTAssertNotNil(err)
            XCTAssertEqual((err! as! ObservableTestError).reason, "2")
        })
        expectResults(observable: o.retry(count: 0), satisfy: {
            XCTAssertEqual($0, [0,1,2,3])
        })
    }
}
