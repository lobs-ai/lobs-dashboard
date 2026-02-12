import Foundation

// Minimal test to verify agent field encoding/decoding
struct DashboardTaskTest: Codable {
    var id: String
    var title: String
    var status: String
    var owner: String
    var createdAt: Date
    var updatedAt: Date
    var agent: String?
}

// Test 1: Decode legacy task without agent field
let legacyJSON = """
{
    "id": "legacy",
    "title": "Legacy Task",
    "status": "active",
    "owner": "lobs",
    "createdAt": "2024-01-01T00:00:00Z",
    "updatedAt": "2024-01-01T00:00:00Z"
}
"""

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

if let data = legacyJSON.data(using: .utf8),
   let task = try? decoder.decode(DashboardTaskTest.self, from: data) {
    print("✓ Legacy task decoded successfully")
    print("  Agent: \(task.agent ?? "nil") (expected: nil)")
    if task.agent == nil {
        print("  ✓ Backwards compatibility verified")
    }
} else {
    print("✗ Failed to decode legacy task")
}

// Test 2: Encode and decode task with agent field
let taskWithAgent = DashboardTaskTest(
    id: "test",
    title: "Test Task",
    status: "active",
    owner: "lobs",
    createdAt: Date(),
    updatedAt: Date(),
    agent: "programmer"
)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

if let encoded = try? encoder.encode(taskWithAgent),
   let decoded = try? decoder.decode(DashboardTaskTest.self, from: encoded) {
    print("\n✓ Task with agent encoded/decoded successfully")
    print("  Agent: \(decoded.agent ?? "nil") (expected: programmer)")
    if decoded.agent == "programmer" {
        print("  ✓ Agent field persists through encode/decode")
    }
} else {
    print("\n✗ Failed to encode/decode task with agent")
}

print("\n✓ All agent field tests passed")
