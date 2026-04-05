class AgentRegistration < ApplicationRecord
  belongs_to :workspace

  STATUSES = %w[online offline busy].freeze

  validates :agent_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :capabilities, presence: true

  scope :online, -> { where(status: "online").where("last_seen_at > ?", 30.seconds.ago) }

  # Returns online agents that declare all required capabilities.
  # An empty +required+ list matches any online agent.
  scope :capable_of, ->(required) {
    return online if required.blank?
    online.where("capabilities @> ?", required.to_json)
  }
end
