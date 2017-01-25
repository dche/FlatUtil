
import Foundation
import Dispatch
import XCTest
@testable import FlatUtil

class FutureTests: XCTestCase {

    enum TestError: Error {
        case a
    }

    func testNormalExecution() {
        let f: Future<Int> = Future { return 1 + 1 }
        let res = f.result()
        XCTAssert(f.isCompleted)
        XCTAssertEqual(res.value!, 2)
    }

    func testLengthyOperation() {
        let f: Future<Int> = Future {
            usleep(5000)
            return 1 + 1
        }
        var res = f.result(timeout: 3.milliseconds)
        XCTAssertFalse(f.isCompleted)
        XCTAssertNotNil(res.error)
        res = f.result()
        XCTAssert(f.isCompleted)
        XCTAssertNil(res.error)
        XCTAssertEqual(res.value!, 2)
    }

    func testErrorResult() {
        let f: Future<String> = Future(error: TestError.a)
        let res = f.result()
        XCTAssert(f.isCompleted)
        XCTAssertNil(res.value)
        XCTAssertNotNil(res.error)
        XCTAssertEqual(res.error! as! TestError, TestError.a)
    }

    func testMap() {
        let f: Future<Int> = Future { 1 + 1 }
        let g = f.map { .value($0 + 3) }
        let e = g.map { $0 * 2 }
        let res = g.result()
        XCTAssertEqual(res.value!, 5)
        XCTAssertEqual(e.result().value!, 10)
    }

    func testAndThen() {
        var sideEffect: Int = 0
        let f: Future<Int> = Future { 1 + 1 }
        let g: Future<()> = f.andThen { i in
            let f: Future<()> = Future {
                sideEffect = i
            }
            return f
        }
        let _ = g.result()
        XCTAssertEqual(sideEffect, 2)
    }

    func testFallback() {
        let f: Future<Int> = Future {
            usleep(1_000)
            throw TestError.a
        }
        let b: () -> Future<Int> = {
            Future(value: 100)
        }
        let g = f.fallback(operation: b)
        var r = g.result()
        XCTAssertEqual(r.value!, 100)

        let h = Future(value: 0).fallback(operation: b)
        r = h.result()
        XCTAssertEqual(r.value!, 0)
    }

    func testJoin() {
        let f: Future<Int> = Future {
            usleep(4_000)
            return 1 + 1
        }
        let g: Future<String> = Future {
            usleep(30)
            return "2"
        }
        let h = f.join(g) {
            Future(value: "\($0) == \($1)")
        }
        var r = h.result(timeout: 1.milliseconds)
        XCTAssertNotNil(r.error)
        XCTAssertFalse(f.isCompleted)
        XCTAssert(g.isCompleted)
        XCTAssertFalse(h.isCompleted)
        r = h.result()
        XCTAssert(h.isCompleted)
        XCTAssertEqual(r.value!, "2 == 2")
    }

    func testPromise() {
        let f: Future<Int> = Future(value: 100)
        XCTAssert(f.isCompleted)
        XCTAssertEqual(f.result().value!, 100)
    }

    func testMulithreadAwait() {
        // TODO: Use C11 `stdatomic` when it is available in SWIFT.
        // var sideEffect: Int32 = 0
        // let f: Future<Int32> = Future {
        //     usleep(50)
        //     return Int32(1)
        // }
        // let n = 1_000
        // for _ in 0..<n {
        //     let _: Future<Void> = f.map {
        //         OSAtomicAdd32($0, &sideEffect)
        //         return .value(())
        //     }
        // }
        // let w: Future<Void> = f.map { _ in
        //     usleep(1_000)
        // }
        // let _ = w.result()
        // XCTAssertEqual(sideEffect, Int32(n))
    }

    func testLongCompositionChain() {
        var f: Future<Int> = Future {
            usleep(10)
            return 0
        }
        let n = 1_000
        for _ in 0..<n {
            f = f.andThen { i in
                return Future {
                    usleep(10)
                    return i + 1
                }
            }
        }
        let i = f.result(timeout: 1.seconds).value!
        XCTAssertEqual(i, n)
    }

    func testLongJoinChain() {
        var fn_1 = Future(value: 1)
        var fn = Future(value: 1)
        let op = { (i: Int, j: Int) in
            Future<Int> {
                // TODO: Randomly set waiting time.
                usleep(10)
                return i + j
            }
        }
        for _ in 2..<50 {
            let f = fn.join(fn_1, operation: op)
            fn_1 = fn
            fn = f
        }
        let f_50 = fn.result().value!
        XCTAssertEqual(f_50, 12586269025)
    }

    func testCustomDispatchQueue() {
        let dp = DispatchQueue(label: "com.eleuth.flat.util.future.tests", qos: .utility)
        let f = Future(dispatchQueue: dp) { () -> String in
            usleep(100)
            return "Flat"
        }
        let p = f.andThen { Future(value: $0 + "Util") }
        XCTAssertEqual(p.result().value!, "FlatUtil")
    }
}
