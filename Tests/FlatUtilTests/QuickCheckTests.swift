
import XCTest
import FlatUtil

class GenTests: XCTestCase {

    func testFilter() {
        let gen = Gen<UInt32>().map { $0 % 1_000 }.filter { $0 % 5 == 0 }
        XCTAssert(quickCheck(gen, size: 100) {
            $0 % 5 == 0
        })
    }

    func testMap() {
        let gen = ["a", "b", "c"].gen().map { $0 + "d" }
        XCTAssert(quickCheck(gen, size: 100) {
            $0.characters.count == 2 && $0.hasSuffix("d")
        })
    }

    func testFlatMap() {
        let gen = (1...100).gen()
        let fgen: (Int) -> Gen<String> = { i in
            return (0..<i).gen().map { "\($0)" }
        }
        XCTAssert(quickCheck(gen.flatMap(fgen), size: 100) {
            $0.characters.count > 0
        })
    }

    func testMakeIterator() {
        for f in Gen<Float>().makeIterator(size: 100) {
            XCTAssert(f < 1 && f >= 0)
        }
    }

    func testTwo() {
        let vecgen = Gen<Float>().two()
        XCTAssert(quickCheck(vecgen, size: 100) {
            $0.0 + $0.1 == $0.1 + $0.0
        })
    }
}

class QuickCheckTests: XCTestCase {

    func sieve(_ n: UInt) -> [UInt] {
        var ps = [UInt]()
        for i in 2..<n {
            var f = true
            for p in ps where p * p < n {
                guard n % p != 0 else {
                    f = false
                    break
                }
            }
            if f { ps.append(i) }
        }
        return ps
    }

    func isPrime(_ i: UInt) -> Bool {
        for p in 2..<i where p * p < i {
            guard i % p != 0 else {
                return false
            }
        }
        return true
    }

    func testAllPrime() {
        let b = quickCheck(sieve(200).gen(), size: 1_000) {
            isPrime($0)
        }
        XCTAssert(b)
    }

    func testProperty() {
        let prop = Property("All numbers should be prime.") {
            self.isPrime($0)
        }
        XCTAssert(prop.check(sieve(100).gen(), size: 1_000))
    }

    func testFailed() {
        let b = quickCheck((1...100).gen(), size: 1_000) {
            $0 < 100
        }
        XCTAssertFalse(b)
    }
}
