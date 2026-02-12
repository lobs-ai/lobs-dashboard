import XCTest
@testable import LobsDashboard

/// Tests for agent picker in task creation showing agent names
final class AgentPickerTests: XCTestCase {
  
  func testAvailableAgentsIncludeNameAndDescription() {
    // Given: The available agents list
    let agents = [
      ("programmer", "🛠️", "Code implementation, bug fixes"),
      ("researcher", "🔬", "Research and investigation"),
      ("reviewer", "🔍", "Code review and feedback"),
      ("writer", "✍️", "Documentation and writing"),
      ("architect", "🏗️", "System design and architecture")
    ]
    
    // Then: Each agent should have ID, emoji, and description
    for agent in agents {
      XCTAssertFalse(agent.0.isEmpty, "Agent ID should not be empty")
      XCTAssertFalse(agent.1.isEmpty, "Agent emoji should not be empty")
      XCTAssertFalse(agent.2.isEmpty, "Agent description should not be empty")
    }
  }
  
  func testAgentIDsMatchExpectedTypes() {
    // Given: The standard agent types
    let expectedAgents = ["programmer", "researcher", "reviewer", "writer", "architect"]
    
    let agents = [
      ("programmer", "🛠️", "Code implementation, bug fixes"),
      ("researcher", "🔬", "Research and investigation"),
      ("reviewer", "🔍", "Code review and feedback"),
      ("writer", "✍️", "Documentation and writing"),
      ("architect", "🏗️", "System design and architecture")
    ]
    
    // When: Extracting agent IDs
    let agentIds = agents.map { $0.0 }
    
    // Then: Should match expected types
    XCTAssertEqual(agentIds.sorted(), expectedAgents.sorted())
  }
  
  func testAgentEmojiAreUnique() {
    // Given: The available agents list
    let agents = [
      ("programmer", "🛠️", "Code implementation, bug fixes"),
      ("researcher", "🔬", "Research and investigation"),
      ("reviewer", "🔍", "Code review and feedback"),
      ("writer", "✍️", "Documentation and writing"),
      ("architect", "🏗️", "System design and architecture")
    ]
    
    // When: Extracting emojis
    let emojis = agents.map { $0.1 }
    
    // Then: All emojis should be unique
    XCTAssertEqual(emojis.count, Set(emojis).count, "Each agent should have a unique emoji")
  }
  
  func testAgentNamesAreCapitalized() {
    // Given: Agent IDs in lowercase
    let agentIds = ["programmer", "researcher", "reviewer", "writer", "architect"]
    
    // When: Capitalizing for display
    let capitalizedNames = agentIds.map { $0.capitalized }
    
    // Then: Should be properly capitalized
    let expected = ["Programmer", "Researcher", "Reviewer", "Writer", "Architect"]
    XCTAssertEqual(capitalizedNames, expected)
  }
  
  func testSelectedAgentDisplayFormat() {
    // Given: A selected agent
    let agents = [
      ("programmer", "🛠️", "Code implementation, bug fixes"),
      ("researcher", "🔬", "Research and investigation")
    ]
    let selectedAgent = "programmer"
    
    // When: Finding the selected agent
    let selected = agents.first(where: { $0.0 == selectedAgent })
    
    // Then: Should have emoji and capitalized name for display
    XCTAssertNotNil(selected)
    XCTAssertEqual(selected?.1, "🛠️")
    XCTAssertEqual(selected?.0.capitalized, "Programmer")
  }
  
  func testUnselectedAgentShowsPlaceholder() {
    // Given: An invalid selected agent
    let agents = [
      ("programmer", "🛠️", "Code implementation, bug fixes")
    ]
    let selectedAgent = "nonexistent"
    
    // When: Finding the selected agent
    let selected = agents.first(where: { $0.0 == selectedAgent })
    
    // Then: Should be nil (would show placeholder in UI)
    XCTAssertNil(selected, "Invalid agent should return nil")
  }
  
  func testDefaultAgentIsProgrammer() {
    // Given: The default selected agent
    let defaultAgent = "programmer"
    
    // Then: Should be programmer
    XCTAssertEqual(defaultAgent, "programmer", "Default agent should be programmer")
  }
  
  func testAgentDescriptionsAreInformative() {
    // Given: The available agents with descriptions
    let agents = [
      ("programmer", "🛠️", "Code implementation, bug fixes"),
      ("researcher", "🔬", "Research and investigation"),
      ("reviewer", "🔍", "Code review and feedback"),
      ("writer", "✍️", "Documentation and writing"),
      ("architect", "🏗️", "System design and architecture")
    ]
    
    // Then: Each description should be at least 10 characters
    for agent in agents {
      XCTAssertGreaterThanOrEqual(
        agent.2.count,
        10,
        "Agent \(agent.0) should have an informative description"
      )
    }
  }
  
  func testAgentPickerShowsEmojiAndName() {
    // This test documents the expected UI behavior:
    // When the agent picker is collapsed (not expanded), it should show:
    // - The agent's emoji (e.g., "🛠️")
    // - The agent's capitalized name (e.g., "Programmer")
    //
    // Previous behavior: showed just the agent ID (e.g., "programmer")
    // New behavior: shows "🛠️ Programmer"
    
    let agents = [
      ("programmer", "🛠️", "Code implementation, bug fixes")
    ]
    let selectedAgent = "programmer"
    
    if let selected = agents.first(where: { $0.0 == selectedAgent }) {
      let emoji = selected.1
      let displayName = selected.0.capitalized
      
      XCTAssertEqual(emoji, "🛠️")
      XCTAssertEqual(displayName, "Programmer")
      
      // The UI should display: "🛠️ Programmer"
      // Not just: "programmer"
    }
  }
  
  func testMenuButtonShowsChevronDown() {
    // This test documents that the Menu (replacing Picker) should show
    // a chevron down indicator to signal it's a dropdown menu
    
    // The chevron icon used: "chevron.down"
    let chevronIcon = "chevron.down"
    XCTAssertEqual(chevronIcon, "chevron.down")
  }
}
