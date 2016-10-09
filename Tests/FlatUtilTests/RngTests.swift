
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
}
