//
//  NSGTests.swift
//  NSGTests
//

import Testing
@testable import NSG

struct NSGTests {

    @Test("Basic smoke test")
    func basicTest() {
        #expect(1 + 1 == 2)
    }

}
