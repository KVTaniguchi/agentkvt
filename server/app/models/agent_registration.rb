class AgentRegistration < ApplicationRecord
  belongs_to :workspace

  STATUSES = %w[online offline busy].freeze

  validates :agent_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :capabilities_must_be_array

  # Heartbeat interval on the Mac is ~15s; allow several missed beats before treating as offline.
  scope :online, -> { where(status: "online").where("last_seen_at > ?", 90.seconds.ago) }

  # Returns online agents that declare all required capabilities.
  # An empty +required+ list matches any online agent.
  scope :capable_of, ->(required) {
    return online if required.blank?
    online.where("capabilities @> ?", required.to_json)
  }

  private

  def capabilities_must_be_array
    errors.add(:capabilities, "must be an array") unless capabilities.is_a?(Array)
  end
end
