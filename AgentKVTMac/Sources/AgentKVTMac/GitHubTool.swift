import Foundation

/// GitHub MCP tool: authenticated with a dedicated Bot PAT; only designated repos (allowlist).
/// The token must be scoped exclusively to agent-accessible repositories.
public func makeGitHubTool(
    pat: String,
    allowedRepos: [String] // e.g. ["owner/repo1", "owner/repo2"]
) -> ToolRegistry.Tool {
    let allowSet = Set(allowedRepos.map { $0.lowercased() })
    return ToolRegistry.Tool(
        id: "github_agent",
        name: "github_agent",
        description: "Perform read-only GitHub operations on allowed repositories. List issues or get repo info. Only repos in the allowlist can be accessed.",
        parameters: .init(
            type: "object",
            properties: [
                "action": .init(type: "string", description: "One of: list_issues"),
                "owner": .init(type: "string", description: "Repository owner (e.g. octocat)"),
                "repo": .init(type: "string", description: "Repository name (e.g. hello-world)")
            ],
            required: ["action", "owner", "repo"]
        ),
        handler: { args in
            guard let action = args["action"] as? String,
                  let owner = args["owner"] as? String, !owner.isEmpty,
                  let repo = args["repo"] as? String, !repo.isEmpty else {
                return "Error: action, owner, and repo are required."
            }
            let key = "\(owner)/\(repo)".lowercased()
            guard allowSet.contains(key) else {
                return "Error: repository \(owner)/\(repo) is not in the allowed list. Cannot access."
            }
            return await GitHubTool.run(action: action, owner: owner, repo: repo, pat: pat)
        }
    )
}

enum GitHubTool {
    static func run(action: String, owner: String, repo: String, pat: String) async -> String {
        guard !pat.isEmpty else { return "Error: GITHUB_AGENT_PAT not configured." }
        switch action {
        case "list_issues":
            return await listIssues(owner: owner, repo: repo, pat: pat)
        default:
            return "Error: unknown action '\(action)'. Supported: list_issues."
        }
    }

    private static func listIssues(owner: String, repo: String, pat: String) async -> String {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues?state=open&per_page=10")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "Error: invalid response." }
            guard http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "\(http.statusCode)"
                return "GitHub API error (\(http.statusCode)): \(msg)"
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            let lines = json.prefix(10).map { issue -> String in
                let title = issue["title"] as? String ?? "?"
                let number = issue["number"] as? Int ?? 0
                let state = issue["state"] as? String ?? "?"
                return "#\(number) [\(state)] \(title)"
            }
            return "Open issues:\n" + lines.joined(separator: "\n")
        } catch {
            return "Error: \(error)"
        }
    }
}
