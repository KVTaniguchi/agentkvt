class SlackWorkspaceLink < ApplicationRecord
  belongs_to :workspace

  validates :slack_team_id, presence: true, uniqueness: true
end
