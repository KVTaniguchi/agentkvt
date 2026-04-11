module Slack
  class WorkspaceResolver
    def self.call(team_id:)
      return nil if team_id.blank?

      link = SlackWorkspaceLink.find_by(slack_team_id: team_id)
      return link.workspace if link

      if ENV["SLACK_TEAM_ID"].present? && ENV["SLACK_TEAM_ID"] == team_id
        slug = ENV["SLACK_WORKSPACE_SLUG"].presence ||
          ENV.fetch("DEFAULT_WORKSPACE_SLUG", "default")
        return Workspace.find_by(slug: slug)
      end

      nil
    end
  end
end
