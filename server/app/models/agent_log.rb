class AgentLog < ApplicationRecord
  belongs_to :workspace
  belongs_to :mission, optional: true

  validates :phase, presence: true
  validates :content, presence: true

  scope :recent_first, -> { order(timestamp: :desc, created_at: :desc) }
end
