import ArkavoAgent
import Foundation

@MainActor
class AgentTester {
    let manager = AgentManager(autoConnect: false, autoReconnect: false)

    func runAllTests() async {
        print("📋 Running All Tests")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        await test1_Discovery()
        await test2_Connection()
        await test3_RpcCall()
        await test4_ChatSession()

        print("\n✅ All tests complete")
    }

    func runTest(named name: String) async {
        print("📋 Running Test: \(name)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        switch name.lowercased() {
        case "discovery":
            await test1_Discovery()
        case "connection":
            await test2_Connection()
        case "rpc":
            await test3_RpcCall()
        case "chat":
            await test4_ChatSession()
        default:
            print("❌ Unknown test: \(name)")
            print("Available tests: discovery, connection, rpc, chat")
        }
    }

    // MARK: - Test 1: Discovery

    func test1_Discovery() async {
        print("📡 Test 1: mDNS Discovery")
        print("─────────────────────────────────────────────────\n")

        // Start discovery
        manager.startDiscovery()
        print("✓ Started mDNS discovery for _a2a._tcp.local.")
        print("  (Browsing for arkavo-edge agents...)\n")

        // Wait for agents with progress indicator
        print("⏳ Waiting for agents (10s timeout)...")
        var elapsed = 0
        while manager.agents.isEmpty && elapsed < 10 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            elapsed += 1
            print("  \(elapsed)s...", terminator: elapsed % 5 == 0 ? "\n" : " ")
        }
        print("")

        if manager.agents.isEmpty {
            print("❌ FAIL: No agents discovered")
            print("   Ensure arkavo-edge is running on the same network")
            print("   Start it with: arkavo\n")
            return
        }

        print("✅ PASS: Discovered \(manager.agents.count) agent(s)\n")

        for (i, agent) in manager.agents.enumerated() {
            print("Agent [\(i)]:")
            print("  ID:       \(agent.id)")
            print("  Name:     \(agent.metadata.name)")
            print("  URL:      \(agent.url)")
            print("  Model:    \(agent.metadata.model)")
            print("  Purpose:  \(agent.metadata.purpose)")
            print("  Uses TLS: \(agent.usesTLS ? "Yes" : "No")")
            if let host = agent.host, let port = agent.port {
                print("  Host:     \(host):\(port)")
            }
            print("")
        }

        // Stop discovery
        manager.stopDiscovery()
        print("✓ Stopped discovery\n")
    }

    // MARK: - Test 2: Connection

    func test2_Connection() async {
        print("🔌 Test 2: WebSocket Connection")
        print("─────────────────────────────────────────────────\n")

        // Ensure we have agents
        if !manager.isDiscovering {
            manager.startDiscovery()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        guard let agent = manager.agents.first else {
            print("❌ SKIP: No agents available for connection test")
            print("   Run discovery test first\n")
            return
        }

        print("🎯 Target: \(agent.metadata.name) at \(agent.url)")
        print("")

        do {
            // Attempt connection
            print("⏳ Connecting...")
            try await manager.connect(to: agent)

            // Check status
            let status = manager.statuses[agent.id]
            print("✅ PASS: Connected successfully")
            print("  Status: \(String(describing: status))")

            // Verify connection at transport level
            if let connection = manager.getConnection(for: agent.id) {
                let isConnected = await connection.isConnected()
                print("  Transport connected: \(isConnected)")
            }
            print("")

            // Disconnect
            await manager.disconnect(from: agent.id)
            print("✓ Disconnected\n")

        } catch {
            print("❌ FAIL: Connection failed")
            print("  Error: \(error.localizedDescription)\n")
        }
    }

    // MARK: - Test 3: RPC Call

    func test3_RpcCall() async {
        print("📞 Test 3: JSON-RPC Request/Response")
        print("─────────────────────────────────────────────────\n")

        guard let agent = manager.agents.first else {
            print("❌ SKIP: No agents available\n")
            return
        }

        do {
            // Connect
            try await manager.connect(to: agent)
            print("✓ Connected to \(agent.metadata.name)\n")

            // Send rpc.discover request
            print("→ Sending: rpc.discover")
            let response = try await manager.sendRequest(
                to: agent.id,
                method: "rpc.discover",
                params: [:]
            )

            switch response {
            case .success(let id, let result):
                print("✅ PASS: Received response")
                print("  Request ID: \(id)")
                print("  Result: \(result.value)")
                print("")

            case .error(let id, let code, let message):
                print("❌ FAIL: RPC error")
                print("  Request ID: \(id)")
                print("  Error code: \(code)")
                print("  Message: \(message)")
                print("")
            }

            // Cleanup
            await manager.disconnect(from: agent.id)

        } catch {
            print("❌ FAIL: RPC call failed")
            print("  Error: \(error.localizedDescription)\n")
        }
    }

    // MARK: - Test 4: Chat Session

    func test4_ChatSession() async {
        print("💬 Test 4: Chat Session")
        print("─────────────────────────────────────────────────\n")

        guard let agent = manager.agents.first else {
            print("❌ SKIP: No agents available\n")
            return
        }

        let chatManager = AgentChatSessionManager(agentManager: manager)

        do {
            // Connect
            try await manager.connect(to: agent)
            print("✓ Connected to \(agent.metadata.name)\n")

            // Open chat session
            print("⏳ Opening chat session...")
            let session = try await chatManager.openSession(with: agent.id)
            print("✅ Session opened")
            print("  Session ID: \(session.id)")
            print("  Created at: \(session.createdAt)")
            print("")

            // Send message
            let message = "Hello from ArkavoAgent test! Can you respond?"
            print("→ Sending message: '\(message)'")
            try await chatManager.sendMessage(
                sessionId: session.id,
                content: message
            )
            print("✓ Message sent\n")

            // Note: In real implementation, would subscribe to deltas here
            // For now, just wait a moment
            print("⏳ Waiting for response (simulated - full streaming not impl in test)")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            print("")

            // Close session
            print("⏳ Closing session...")
            await chatManager.closeSession(sessionId: session.id)
            print("✅ PASS: Session closed\n")

            // Cleanup
            await manager.disconnect(from: agent.id)

        } catch {
            print("❌ FAIL: Chat session failed")
            print("  Error: \(error.localizedDescription)\n")
        }
    }
}
