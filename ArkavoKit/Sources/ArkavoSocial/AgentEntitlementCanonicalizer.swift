import Foundation

public enum AgentEntitlementCanonicalizer {
    public static let namespace = "https://arkavo.ai/attr"
    private static let bare: Set<String> = ["read", "write", "execute", "delegate", "admin"]

    public static func canonicalize(_ raw: [String]) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        for item in raw.map({ $0.trimmingCharacters(in: .whitespaces) }) where !item.isEmpty {
            if item.hasPrefix("https://"), item.contains("/attr/"), item.contains("/value/") { add(item); continue }
            switch item.lowercased() {
            case "agent.capability.chat", "chat":
                add("\(namespace)/action/value/read"); add("\(namespace)/action/value/write")
            case "agent.capability.tools", "tools":
                add("\(namespace)/action/value/execute")
            case let w where bare.contains(w):
                add("\(namespace)/action/value/\(w)")
            default:
                continue
            }
        }
        return out
    }
}
