import XCTest
@testable import ArkavoSocial

final class AgentEntitlementCanonicalizerTests: XCTestCase {
    func test_fqnPassesThrough() {
        XCTAssertEqual(AgentEntitlementCanonicalizer.canonicalize(["https://arkavo.ai/attr/tdf/value/decrypt"]),
                       ["https://arkavo.ai/attr/tdf/value/decrypt"])
    }
    func test_legacyCapabilitiesMap() {
        XCTAssertEqual(AgentEntitlementCanonicalizer.canonicalize(["agent.capability.chat", "agent.capability.tools"]),
                       ["https://arkavo.ai/attr/action/value/read",
                        "https://arkavo.ai/attr/action/value/write",
                        "https://arkavo.ai/attr/action/value/execute"])
    }
    func test_bareWordsDedupAndUnknownDropped() {
        XCTAssertEqual(AgentEntitlementCanonicalizer.canonicalize(["read", "read", "banana", "admin"]),
                       ["https://arkavo.ai/attr/action/value/read", "https://arkavo.ai/attr/action/value/admin"])
    }
}
