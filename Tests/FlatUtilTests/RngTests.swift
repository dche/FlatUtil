
import XCTest
import FlatUtil

class RngTests: XCTestCase {

    func testDevRandom() {
        var rng = DevRandom()
        XCTAssertNotEqual(rng.nextUInt64(), rng.nextUInt64())
    }

    func testXoroshiro() {
        var rng = Xoroshiro()
        XCTAssertNotEqual(rng.nextUInt32(), rng.nextUInt32())
    }

    func testDefaultRng() {
        let f = Float.random()
        let f1 = Float.random()
        XCTAssertNotEqual(f, f1)
        XCTAssertNotEqual(f1, Float.random())
        XCTAssertNotEqual(f1, Float.random())
    }
}
