@testable import Arkavo
import CryptoKit
import XCTest

class UserActionTests: XCTestCase {
    // Sample user IDs and Target Object IDs
    var userID: UUID!
    var targetObjectID: UUID!

    override func setUp() {
        super.setUp()
        userID = UUID()
        targetObjectID = UUID()
    }

    func testInit() {
        let actionType: ActionType = .join
        let targetLifecycleState: LifecycleState = .preparing
        let status: ActionStatus = .preparing
        let userAction = UserAction(userID: userID, targetObjectID: targetObjectID, actionType: actionType, targetLifecycleState: targetLifecycleState, status: status)

        XCTAssertEqual(userAction.userID, userID)
        XCTAssertEqual(userAction.targetObjectID, targetObjectID)
        XCTAssertEqual(userAction.actionType, actionType)
        XCTAssertEqual(userAction.targetLifecycleState, targetLifecycleState)
        XCTAssertEqual(userAction.status, status)
    }

    func testPublicID() {
        let actionType: ActionType = .join
        let targetLifecycleState: LifecycleState = .preparing
        let status: ActionStatus = .preparing
        let userAction = UserAction(userID: userID, targetObjectID: targetObjectID, actionType: actionType, targetLifecycleState: targetLifecycleState, status: status)

        let hashData = userID.uuidString.data(using: .utf8)! + targetObjectID.uuidString.data(using: .utf8)! + actionType.rawValue.data(using: .utf8)!
        let expectedHash = SHA256.hash(data: hashData).withUnsafeBytes { Data($0) }

        XCTAssertEqual(userAction.publicID, expectedHash)
    }

    func testSerializeDeserialize() {
        let actionType: ActionType = .join
        let targetLifecycleState: LifecycleState = .preparing
        let status: ActionStatus = .preparing
        let userAction = UserAction(userID: userID, targetObjectID: targetObjectID, actionType: actionType, targetLifecycleState: targetLifecycleState, status: status)

        do {
            let serializedData = try userAction.serialize()
            let deserializedAction = try UserAction.deserialize(from: serializedData)

            XCTAssertEqual(deserializedAction.userID, userID)
            XCTAssertEqual(deserializedAction.targetObjectID, targetObjectID)
            XCTAssertEqual(deserializedAction.actionType, actionType)
            XCTAssertEqual(deserializedAction.targetLifecycleState, targetLifecycleState)
            XCTAssertEqual(deserializedAction.status, status)
            XCTAssertEqual(deserializedAction.publicID, userAction.publicID)
        } catch {
            XCTFail("Serialization/Deserialization failed with error: \(error)")
        }
    }

    func testPublicIDString() {
        let actionType: ActionType = .join
        let targetLifecycleState: LifecycleState = .preparing
        let status: ActionStatus = .preparing
        let userAction = UserAction(userID: userID, targetObjectID: targetObjectID, actionType: actionType, targetLifecycleState: targetLifecycleState, status: status)

        XCTAssertFalse(userAction.publicIDString.isEmpty)
    }
}
