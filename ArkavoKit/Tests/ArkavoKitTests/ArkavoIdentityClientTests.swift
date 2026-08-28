import XCTest
@testable import ArkavoSocial

final class ArkavoIdentityClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.handler = nil
    }

    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    /// Reads the request body regardless of whether `URLSession`/`URLProtocol`
    /// populated `httpBody` or delivered it as `httpBodyStream` (stubs
    /// typically do the latter).
    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// `URLRequest.url?.path` returns the *decoded* path (Foundation un-escapes
    /// percent-encoding when reading `.path`), so assertions that need to see
    /// the literal wire-encoded segment (e.g. `%3A` for `:`) must read
    /// `percentEncodedPath` via `URLComponents` instead.
    private func percentEncodedPath(of request: URLRequest?) -> String? {
        guard let url = request?.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
    }

    private func makeClient(token: String? = "CWT") -> ArkavoIdentityClient {
        ArkavoIdentityClient(
            baseURL: URL(string: "https://identity.test")!,
            session: URLProtocolStub.session(),
            tokenProvider: { token }
        )
    }

    // MARK: - /agents/authorize

    func test_authorize_sendsXAuthTokenAndAgentDid() async throws {
        var captured: URLRequest?
        URLProtocolStub.handler = { req in
            captured = req
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let client = makeClient()
        try await client.authorizeAgent(did: "did:key:z6Mk", name: "n", entitlements: ["https://arkavo.ai/attr/action/value/read"])

        XCTAssertEqual(captured?.url?.path, "/agents/authorize")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "X-Auth-Token"), "CWT")
        XCTAssertNil(captured?.value(forHTTPHeaderField: "Authorization"))

        let bodyJSON = try XCTUnwrap(bodyData(from: try XCTUnwrap(captured)))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyJSON) as? [String: Any])
        XCTAssertEqual(body["agent_did"] as? String, "did:key:z6Mk")
        XCTAssertEqual(body["name"] as? String, "n")
        XCTAssertEqual(body["entitlements"] as? [String], ["https://arkavo.ai/attr/action/value/read"])
    }

    func test_authorize_409IsSuccess_401Unauthorized() async throws {
        let client = makeClient()

        // 409 (already delegated) is treated as success -- must not throw.
        URLProtocolStub.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!, Data("already delegated".utf8))
        }
        try await client.authorizeAgent(did: "did:key:z6Mk", name: "n", entitlements: ["x"])

        // 401 must surface as .unauthorized.
        URLProtocolStub.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("nope".utf8))
        }
        do {
            try await client.authorizeAgent(did: "did:key:z6Mk", name: "n", entitlements: ["x"])
            XCTFail("expected .unauthorized")
        } catch {
            XCTAssertEqual(error as? ArkavoIdentityError, .unauthorized)
        }
    }

    func test_missingToken_failsFast() async {
        URLProtocolStub.handler = { _ in
            XCTFail("must not send")
            throw URLError(.badURL)
        }
        let client = makeClient(token: nil)
        do {
            try await client.authorizeAgent(did: "d", name: "n", entitlements: ["x"])
            XCTFail("expected .notAuthenticated")
        } catch {
            XCTAssertEqual(error as? ArkavoIdentityError, .notAuthenticated)
        }
    }

    // MARK: - /agents/delegations

    func test_listDelegations_decodesSnakeCase() async throws {
        URLProtocolStub.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"delegations":[{"agent_did":"did:key:z6Mk","name":"a","entitlements":["e"],"depth":0,"created_at":1,"expires_at":2,"revoked":false}]}"#.utf8))
        }
        let client = makeClient()
        let list = try await client.listDelegations()
        XCTAssertEqual(list.first?.agentDid, "did:key:z6Mk")
        XCTAssertEqual(list.first?.expiresAt, 2)
        XCTAssertEqual(list.first?.name, "a")
        XCTAssertEqual(list.first?.entitlements, ["e"])
        XCTAssertEqual(list.first?.depth, 0)
        XCTAssertEqual(list.first?.createdAt, 1)
        XCTAssertEqual(list.first?.revoked, false)
    }

    func test_listDelegations_expiresAtNullDecodesToNil() async throws {
        URLProtocolStub.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"delegations":[{"agent_did":"did:key:z6Mk","name":"a","entitlements":[],"depth":0,"created_at":1,"expires_at":null,"revoked":false}]}"#.utf8))
        }
        let client = makeClient()
        let list = try await client.listDelegations()
        XCTAssertNil(list.first?.expiresAt)
    }

    func test_revoke_204() async throws {
        var captured: URLRequest?
        URLProtocolStub.handler = { req in
            captured = req
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = makeClient()
        try await client.revokeDelegation(did: "did:key:z6Mk")

        XCTAssertEqual(captured?.httpMethod, "DELETE")
        // The did contains colons and must be percent-encoded as a path segment.
        XCTAssertEqual(percentEncodedPath(of: captured), "/agents/delegations/did%3Akey%3Az6Mk")
    }

    // MARK: - /device-check/challenge

    func test_deviceCheckChallenge_pathSegmentEncodingAndDecoding() async throws {
        var captured: URLRequest?
        URLProtocolStub.handler = { req in
            captured = req
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"challenge":"abc-123"}"#.utf8))
        }
        let client = makeClient(token: nil) // challenge does not require a token
        let challenge = try await client.deviceCheckChallenge(username: "paul@arkavo.com")

        XCTAssertEqual(challenge, "abc-123")
        XCTAssertEqual(captured?.httpMethod, "GET")
        XCTAssertEqual(percentEncodedPath(of: captured), "/device-check/challenge/paul%40arkavo.com")
    }

    // MARK: - /device-check/attest

    func test_deviceCheckAttest_sendsBase64EncodedFields() async throws {
        var captured: URLRequest?
        URLProtocolStub.handler = { req in
            captured = req
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"success":true,"message":"ok"}"#.utf8))
        }
        let client = makeClient(token: nil)
        let attestationObject = Data([0x01, 0x02, 0x03])
        let clientDataHash = Data([0xAA, 0xBB])
        try await client.deviceCheckAttest(keyId: "key-1", attestationObject: attestationObject, clientDataHash: clientDataHash)

        XCTAssertEqual(captured?.url?.path, "/device-check/attest")
        let bodyJSON = try XCTUnwrap(bodyData(from: try XCTUnwrap(captured)))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyJSON) as? [String: Any])
        XCTAssertEqual(body["key_id"] as? String, "key-1")
        XCTAssertEqual(body["attestation_object"] as? String, attestationObject.base64EncodedString())
        XCTAssertEqual(body["client_data_hash"] as? String, clientDataHash.base64EncodedString())
    }

    func test_deviceCheckAttest_successFalseThrowsAttestationRejected() async {
        URLProtocolStub.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"success":false,"message":"attestation invalid"}"#.utf8))
        }
        let client = makeClient(token: nil)
        do {
            try await client.deviceCheckAttest(keyId: "key-1", attestationObject: Data(), clientDataHash: Data())
            XCTFail("expected throw when success is false")
        } catch {
            // A 200-status logical rejection must surface as .attestationRejected,
            // NOT .server -- .server is reserved for genuine non-2xx responses.
            XCTAssertEqual(error as? ArkavoIdentityError, .attestationRejected("attestation invalid"))
        }
    }

    // MARK: - /device-check/assert-challenge

    func test_deviceCheckAssertChallenge_sendsXAuthTokenAndPathSegment() async throws {
        var captured: URLRequest?
        URLProtocolStub.handler = { req in
            captured = req
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"challenge":"def-456"}"#.utf8))
        }
        let client = makeClient(token: "CWT")
        let challenge = try await client.deviceCheckAssertChallenge(username: "paul@arkavo.com")

        XCTAssertEqual(challenge, "def-456")
        XCTAssertEqual(percentEncodedPath(of: captured), "/device-check/assert-challenge/paul%40arkavo.com")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "X-Auth-Token"), "CWT")
    }

    // MARK: - /device-check/assert

    func test_deviceCheckAssert_readsTokenFromJSONBody() async throws {
        URLProtocolStub.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-Auth-Token": "should-be-ignored"])!,
             Data(#"{"token":"device-cwt-abc"}"#.utf8))
        }
        let client = makeClient(token: nil)
        let token = try await client.deviceCheckAssert(keyId: "key-1", assertion: Data([0x01]), clientDataHash: Data([0x02]))
        XCTAssertEqual(token, "device-cwt-abc")
    }
}
