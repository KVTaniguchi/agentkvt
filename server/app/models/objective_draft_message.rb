class ObjectiveDraftMessage < ApplicationRecord
  ROLES = %w[user assistant system].freeze

  belongs_to :objective_draft, touch: true

  scope :chronological, -> { order(timestamp: :asc, created_at: :asc) }

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :content, presence: true
end
