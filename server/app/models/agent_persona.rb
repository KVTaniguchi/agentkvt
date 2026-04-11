class AgentPersona < ApplicationRecord
  CHANNEL_TYPES = %w[email slack].freeze

  belongs_to :workspace

  validates :channel_type, presence: true, inclusion: { in: CHANNEL_TYPES }
  validates :workspace_id, uniqueness: { scope: :channel_type }
end
