class Task < ApplicationRecord
  belongs_to :objective
  has_many :research_snapshots, dependent: :nullify

  STATUSES = %w[pending in_progress completed failed].freeze

  validates :description, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending_first, -> { order(created_at: :asc) }
end
