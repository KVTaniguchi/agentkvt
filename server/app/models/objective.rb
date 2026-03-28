class Objective < ApplicationRecord
  belongs_to :workspace
  has_many :tasks, dependent: :destroy
  has_many :research_snapshots, dependent: :destroy

  STATUSES = %w[pending active completed archived].freeze

  validates :goal, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(priority: :desc, created_at: :desc) }
end
