import ArkavoAgent
import Foundation

@MainActor
class InteractiveCLI {
    let manager = AgentManager(autoConnect: false, autoReconnect: false)
    var activeSessionId: String?
    var activeAgentId: String?

    func run() async {
        printWelcome()

        while true {
            print("> ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
                continue
            }

            if input.isEmpty {
                continue
            }

            let parts = input.split(separator: " ", maxSplits: 1).map(String.init)
            let command = parts[0].lowercased()
            let args = parts.count > 1 ? parts[1] : ""

            switch command {
            case "help", "?":
                printHelp()

            case "discover":
                await cmdDiscover()

            case "list":
                await cmdList()

            case "connect":
                if let index = Int(args) {
                    await cmdConnect(index: index)
                } else {
                    print("❌ Usage: connect <agent-number>")
                }

            case "disconnect":
                if let index = Int(args) {
                    await cmdDisconnect(index: index)
                } else {
                    print("❌ Usage: disconnect <agent-number>")
                }

            case "status":
                await cmdStatus()

            case "chat":
                if let index = Int(args) {
                    await cmdChat(index: index)
                } else {
                    print("❌ Usage: chat <agent-number>")
                }

            case "send":
                if !args.isEmpty {
                    await cmdSend(message: args)
                } else {
                    print("❌ Usage: send <message>")
                }

            case "close":
                await cmdClose()

            case "rpc":
                let rpcParts = args.split(separator: " ", maxSplits: 1).map(String.init)
                if rpcParts.count >= 1 {
                    let method = rpcParts[0]
                    await cmdRpc(method: method)
                } else {
                    print("❌ Usage: rpc <method>")
                }

            case "quit", "exit", "q":
                print("👋 Goodbye!")
                return

            default:
                print("❌ Unknown command: \(command)")
                print("   Type 'help' for available commands")
            }

            print("")
        }
    }

    // MARK: - Commands

    func cmdDiscover() async {
        print("📡 Starting mDNS discovery...")
        manager.startDiscovery()

        print("⏳ Waiting for agents (5s)...")
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        if manager.agents.isEmpty {
            print("❌ No agents found")
        } else {
            print("✓ Found \(manager.agents.count) agent(s)")
            await cmdList()
        }
    }

    func cmdList() async {
        if manager.agents.isEmpty {
            print("No agents discovered. Use 'discover' first.")
            return
        }

        print("Discovered Agents:")
        print("─────────────────────────────────────────────")

        for (i, agent) in manager.agents.enumerated() {
            let status = manager.statuses[agent.id] ?? .disconnected
            let statusIcon = statusIcon(for: status)

            print("[\(i)] \(statusIcon) \(agent.metadata.name)")
            print("    URL:     \(agent.url)")
            print("    Model:   \(agent.metadata.model)")
            print("    Purpose: \(agent.metadata.purpose)")
            print("    Status:  \(statusDescription(status))")
        }
    }

    func cmdConnect(index: Int) async {
        guard index < manager.agents.count else {
            print("❌ Invalid agent number")
            return
        }

        let agent = manager.agents[index]
        print("🔌 Connecting to \(agent.metadata.name)...")

        do {
            try await manager.connect(to: agent)
            print("✅ Connected successfully")
        } catch {
            print("❌ Connection failed: \(error.localizedDescription)")
        }
    }

    func cmdDisconnect(index: Int) async {
        guard index < manager.agents.count else {
            print("❌ Invalid agent number")
            return
        }

        let agent = manager.agents[index]
        print("🔌 Disconnecting from \(agent.metadata.name)...")
        await manager.disconnect(from: agent.id)
        print("✓ Disconnected")
    }

    func cmdStatus() async {
        if manager.agents.isEmpty {
            print("No agents")
            return
        }

        print("Agent Status:")
        print("─────────────────────────────────────────────")

        for agent in manager.agents {
            let status = manager.statuses[agent.id] ?? .disconnected
            let statusIcon = statusIcon(for: status)

            print("\(statusIcon) \(agent.metadata.name)")
            print("  \(statusDescription(status))")
        }

        print("")
        let stats = manager.getConnectionStats()
        print("Summary:")
        print("  Total agents: \(stats["total_agents"] ?? 0)")
        print("  Connected:    \(stats["connected"] ?? 0)")
        print("  Discovering:  \(stats["discovering"] ?? false)")
    }

    func cmdChat(index: Int) async {
        guard index < manager.agents.count else {
            print("❌ Invalid agent number")
            return
        }

        let agent = manager.agents[index]

        // Ensure connected
        if manager.statuses[agent.id] != .connected {
            print("⏳ Connecting to agent...")
            do {
                try await manager.connect(to: agent)
            } catch {
                print("❌ Failed to connect: \(error.localizedDescription)")
                return
            }
        }

        let chatManager = AgentChatSessionManager(agentManager: manager)

        do {
            let session = try await chatManager.openSession(with: agent.id)
            activeSessionId = session.id
            activeAgentId = agent.id

            print("💬 Chat session opened with \(agent.metadata.name)")
            print("   Session ID: \(session.id)")
            print("   Use 'send <message>' to chat")
            print("   Use 'close' to end session")

        } catch {
            print("❌ Failed to open chat: \(error.localizedDescription)")
        }
    }

    func cmdSend(message: String) async {
        guard let sessionId = activeSessionId,
              let agentId = activeAgentId else {
            print("❌ No active chat session")
            print("   Open one with: chat <agent-number>")
            return
        }

        let chatManager = AgentChatSessionManager(agentManager: manager)

        do {
            print("→ You: \(message)")
            try await chatManager.sendMessage(sessionId: sessionId, content: message)
            print("✓ Message sent")
            // Note: Would need to subscribe to deltas to show response

        } catch {
            print("❌ Failed to send: \(error.localizedDescription)")
        }
    }

    func cmdClose() async {
        guard let sessionId = activeSessionId else {
            print("❌ No active session")
            return
        }

        let chatManager = AgentChatSessionManager(agentManager: manager)
        await chatManager.closeSession(sessionId: sessionId)

        activeSessionId = nil
        activeAgentId = nil

        print("✓ Chat session closed")
    }

    func cmdRpc(method: String) async {
        guard let agentId = activeAgentId ?? manager.agents.first?.id else {
            print("❌ No agent available")
            print("   Connect to one with: connect <agent-number>")
            return
        }

        do {
            print("→ Calling: \(method)")
            let response = try await manager.sendRequest(
                to: agentId,
                method: method,
                params: [:]
            )

            switch response {
            case .success(_, let result):
                print("✅ Response:")
                print("   \(result.value)")

            case .error(_, let code, let message):
                print("❌ Error \(code): \(message)")
            }

        } catch {
            print("❌ RPC failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    func printWelcome() {
        print("""

        ArkavoAgent Interactive CLI
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        Type 'help' for available commands

        """)
    }

    func printHelp() {
        print("""
        Available Commands:
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        Discovery:
          discover              Start mDNS discovery
          list                  List discovered agents
          status                Show connection status

        Connection:
          connect <n>           Connect to agent #n
          disconnect <n>        Disconnect from agent #n

        Chat:
          chat <n>              Open chat session with agent #n
          send <message>        Send message to active chat
          close                 Close active chat session

        RPC:
          rpc <method>          Call RPC method (e.g., rpc.discover)

        General:
          help                  Show this help
          quit                  Exit CLI
        """)
    }

    func statusIcon(for status: ConnectionStatus) -> String {
        switch status {
        case .connected:
            return "●"
        case .connecting:
            return "○"
        case .disconnected:
            return "○"
        case .reconnecting:
            return "🔄"
        case .failed:
            return "❌"
        }
    }

    func statusDescription(_ status: ConnectionStatus) -> String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Disconnected"
        case .reconnecting(let attempt):
            return "Reconnecting (attempt \(attempt))"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}
