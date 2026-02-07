import Foundation

/// Service for interacting with GitHub Issues API.
class GitHubService {
  private let baseURL = "https://api.github.com"
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  // MARK: - List Issues

  /// Fetch all issues for a repository.
  func listIssues(owner: String, repo: String, token: String, state: String = "open") async throws -> [GitHubIssue] {
    let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues?state=\(state)")!
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)
    try checkResponse(response)

    let issues = try JSONDecoder.githubDecoder.decode([GitHubIssue].self, from: data)
    return issues
  }

  // MARK: - Create Issue

  /// Create a new issue in a repository.
  func createIssue(owner: String, repo: String, token: String, title: String, body: String?, labels: [String]? = nil) async throws -> GitHubIssue {
    let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let payload: [String: Any] = [
      "title": title,
      "body": body ?? "",
      "labels": labels ?? []
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await session.data(for: request)
    try checkResponse(response)

    let issue = try JSONDecoder.githubDecoder.decode(GitHubIssue.self, from: data)
    return issue
  }

  // MARK: - Update Issue

  /// Update an existing issue.
  func updateIssue(owner: String, repo: String, token: String, issueNumber: Int, title: String?, body: String?, state: String? = nil, labels: [String]? = nil) async throws -> GitHubIssue {
    let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(issueNumber)")!
    var request = URLRequest(url: url)
    request.httpMethod = "PATCH"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var payload: [String: Any] = [:]
    if let title = title { payload["title"] = title }
    if let body = body { payload["body"] = body }
    if let state = state { payload["state"] = state }
    if let labels = labels { payload["labels"] = labels }

    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await session.data(for: request)
    try checkResponse(response)

    let issue = try JSONDecoder.githubDecoder.decode(GitHubIssue.self, from: data)
    return issue
  }

  // MARK: - Close Issue

  /// Close an issue.
  func closeIssue(owner: String, repo: String, token: String, issueNumber: Int) async throws -> GitHubIssue {
    return try await updateIssue(owner: owner, repo: repo, token: token, issueNumber: issueNumber, title: nil, body: nil, state: "closed")
  }

  // MARK: - Assign Issue

  /// Assign users to an issue.
  func assignIssue(owner: String, repo: String, token: String, issueNumber: Int, assignees: [String]) async throws -> GitHubIssue {
    let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(issueNumber)/assignees")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let payload: [String: Any] = ["assignees": assignees]
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await session.data(for: request)
    try checkResponse(response)

    let issue = try JSONDecoder.githubDecoder.decode(GitHubIssue.self, from: data)
    return issue
  }

  // MARK: - Error Handling

  private func checkResponse(_ response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GitHubError.invalidResponse
    }

    // Check rate limiting
    if httpResponse.statusCode == 403,
       let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
       remaining == "0" {
      let resetTime = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset")
      throw GitHubError.rateLimitExceeded(resetAt: resetTime)
    }

    // Check for errors
    switch httpResponse.statusCode {
    case 200...299:
      return
    case 401:
      throw GitHubError.unauthorized
    case 404:
      throw GitHubError.notFound
    case 422:
      throw GitHubError.validationFailed
    default:
      throw GitHubError.httpError(statusCode: httpResponse.statusCode)
    }
  }
}

// MARK: - GitHub Models

struct GitHubIssue: Codable {
  var number: Int
  var title: String
  var body: String?
  var state: String
  var labels: [GitHubLabel]?
  var assignees: [GitHubUser]?
  var createdAt: Date
  var updatedAt: Date
  var closedAt: Date?

  enum CodingKeys: String, CodingKey {
    case number, title, body, state, labels, assignees
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case closedAt = "closed_at"
  }
}

struct GitHubLabel: Codable {
  var name: String
  var color: String?
}

struct GitHubUser: Codable {
  var login: String
}

// MARK: - Errors

enum GitHubError: Error, LocalizedError {
  case invalidResponse
  case unauthorized
  case notFound
  case validationFailed
  case rateLimitExceeded(resetAt: String?)
  case httpError(statusCode: Int)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid response from GitHub API"
    case .unauthorized:
      return "GitHub authentication failed. Check your access token."
    case .notFound:
      return "GitHub resource not found"
    case .validationFailed:
      return "GitHub validation failed. Check request parameters."
    case .rateLimitExceeded(let resetAt):
      if let resetAt = resetAt {
        return "GitHub rate limit exceeded. Resets at \(resetAt)."
      }
      return "GitHub rate limit exceeded"
    case .httpError(let statusCode):
      return "GitHub API error: HTTP \(statusCode)"
    }
  }
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
  static var githubDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
