import ArkavoAgent
import Foundation

@main
struct AgentTestCLI {
    static func main() async {
        print("🚀 ArkavoAgent Test CLI")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")

        let args = CommandLine.arguments

        if args.contains("--interactive") {
            await InteractiveCLI().run()
        } else if args.contains("--test-all") {
            let tester = AgentTester()
            await tester.runAllTests()
        } else if let testIndex = args.firstIndex(of: "--test") {
            if testIndex + 1 < args.count {
                let testName = args[testIndex + 1]
                let tester = AgentTester()
                await tester.runTest(named: testName)
            } else {
                printUsage()
            }
        } else {
            // Default: run all tests
            let tester = AgentTester()
            await tester.runAllTests()
        }
    }

    static func printUsage() {
        print("""
        Usage: ArkavoAgentTest [OPTIONS]

        Options:
          --test-all          Run all automated tests
          --test <name>       Run specific test: discovery, connection, chat
          --interactive       Interactive CLI mode

        Examples:
          swift run ArkavoAgentTest --test-all
          swift run ArkavoAgentTest --test discovery
          swift run ArkavoAgentTest --interactive
        """)
    }
}
