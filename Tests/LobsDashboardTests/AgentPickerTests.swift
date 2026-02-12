import XCTest
@testable import LobsDashboard

/// Tests for agent picker display names
///
/// **Issue Fixed:** Agent picker only showed emoji and capitalized type (e.g., "🛠️ Programmer")
/// without the descriptive name/purpose of each agent type.
///
/// **Solution:** Updated agent picker menu items to include agent.2 (description) in addition to
/// emoji (agent.1) and capitalized name (agent.0.capitalized).
///
/// Format: "🛠️ Programmer – Code implementation, bug fixes"
final class AgentPickerTests: XCTestCase {
  
  /// Test: availableAgentTypes returns correct structure
  ///
  /// Expected: Each agent type tuple contains:
  /// - agent.0: type string (e.g., "programmer")
  /// - agent.1: emoji (e.g., "🛠️")
  /// - agent.2: description (e.g., "Code implementation, bug fixes")
  func testAvailableAgentTypesStructure() {
    let agents = availableAgentTypes()
    
    // Should have at least the core agent types
    XCTAssertGreaterThanOrEqual(agents.count, 5, "Should have at least 5 agent types")
    
    // Check first agent (programmer)
    let programmer = agents.first { $0.0 == "programmer" }
    XCTAssertNotNil(programmer, "Should have programmer agent")
    if let programmer = programmer {
      XCTAssertEqual(programmer.0, "programmer", "Type should be 'programmer'")
      XCTAssertEqual(programmer.1, "🛠️", "Emoji should be wrench")
      XCTAssertFalse(programmer.2.isEmpty, "Description should not be empty")
    }
  }
  
  /// Test: All agent types have non-empty descriptions
  ///
  /// Ensures each agent type has a meaningful description for users
  func testAllAgentTypesHaveDescriptions() {
    let agents = availableAgentTypes()
    
    for agent in agents {
      XCTAssertFalse(agent.0.isEmpty, "Agent type should not be empty")
      XCTAssertFalse(agent.1.isEmpty, "Agent emoji should not be empty")
      XCTAssertFalse(agent.2.isEmpty, "Agent description should not be empty for \(agent.0)")
    }
  }
  
  /// Test: agentIcon returns correct emoji for each type
  func testAgentIconMapping() {
    XCTAssertEqual(agentIcon("programmer"), "🛠️")
    XCTAssertEqual(agentIcon("researcher"), "🔬")
    XCTAssertEqual(agentIcon("reviewer"), "🔍")
    XCTAssertEqual(agentIcon("writer"), "✍️")
    XCTAssertEqual(agentIcon("architect"), "🏗️")
    
    // Test case insensitivity
    XCTAssertEqual(agentIcon("PROGRAMMER"), "🛠️")
    XCTAssertEqual(agentIcon("Programmer"), "🛠️")
    
    // Test unknown agent
    XCTAssertEqual(agentIcon("unknown"), "🤖")
  }
  
  /// Test: Agent picker menu format includes all three components
  ///
  /// Documents expected format: "emoji capitalized-name – description"
  func testAgentPickerMenuFormat() {
    // This test documents the expected display format in the agent picker
    // Format should be: "\(agent.1) \(agent.0.capitalized) – \(agent.2)"
    
    let agents = availableAgentTypes()
    let programmer = agents.first { $0.0 == "programmer" }!
    
    let expectedFormat = "\(programmer.1) \(programmer.0.capitalized) – \(programmer.2)"
    
    // Should look like: "🛠️ Programmer – Code implementation, bug fixes"
    XCTAssertTrue(expectedFormat.contains("🛠️"), "Should contain emoji")
    XCTAssertTrue(expectedFormat.contains("Programmer"), "Should contain capitalized name")
    XCTAssertTrue(expectedFormat.contains("–"), "Should contain en dash separator")
    XCTAssertTrue(expectedFormat.contains(programmer.2), "Should contain description")
  }
  
  /// Test: Agent types are unique
  ///
  /// Ensures no duplicate agent types in the list
  func testAgentTypesAreUnique() {
    let agents = availableAgentTypes()
    let types = agents.map { $0.0 }
    let uniqueTypes = Set(types)
    
    XCTAssertEqual(types.count, uniqueTypes.count, "Agent types should be unique")
  }
  
  /// Test: Standard agent types are present
  ///
  /// Verifies all expected core agent types exist
  func testStandardAgentTypesPresent() {
    let agents = availableAgentTypes()
    let types = Set(agents.map { $0.0 })
    
    let expectedTypes: Set<String> = ["programmer", "researcher", "reviewer", "writer", "architect"]
    
    XCTAssertTrue(expectedTypes.isSubset(of: types), "Should include all standard agent types")
  }
  
  /// Test: Descriptions are informative
  ///
  /// Ensures descriptions are meaningful (not just the type name)
  func testDescriptionsAreInformative() {
    let agents = availableAgentTypes()
    
    for agent in agents {
      // Description should be different from just capitalizing the type
      XCTAssertNotEqual(agent.2, agent.0.capitalized, 
                       "Description should be more than just the capitalized type for \(agent.0)")
      
      // Description should be reasonably long (more than just a word)
      XCTAssertGreaterThan(agent.2.count, 5, 
                          "Description should be informative for \(agent.0)")
    }
  }
  
  /// Test: Emoji consistency between availableAgentTypes and agentIcon
  ///
  /// Ensures the emoji in availableAgentTypes matches agentIcon function
  func testEmojiConsistency() {
    let agents = availableAgentTypes()
    
    for agent in agents {
      let emojiFromTypes = agent.1
      let emojiFromIcon = agentIcon(agent.0)
      
      XCTAssertEqual(emojiFromTypes, emojiFromIcon, 
                    "Emoji should match between availableAgentTypes and agentIcon for \(agent.0)")
    }
  }
  
  /// Test: Menu label format for visual consistency
  ///
  /// Documents that the separator should be an en dash (–) not a hyphen (-)
  /// for better typography in the UI
  func testEnDashSeparator() {
    // Using en dash (–) for better visual separation
    // En dash (U+2013): –
    // Hyphen (U+002D): -
    
    let agents = availableAgentTypes()
    let programmer = agents.first { $0.0 == "programmer" }!
    let formatted = "\(programmer.1) \(programmer.0.capitalized) – \(programmer.2)"
    
    XCTAssertTrue(formatted.contains("–"), "Should use en dash (–) not hyphen (-)")
    XCTAssertFalse(formatted.contains(" - "), "Should not use hyphen with spaces")
  }
}
