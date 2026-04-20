class WorkUnit < ApplicationRecord
  belongs_to :workspace

  STATES = %w[draft pending in_progress completed failed cancelled].freeze

  scope :recent_first, -> { order(created_at: :desc) }
  scope :by_state, ->(state) { where(state: state) }
  scope :claimable, -> { where(state: "pending").where("claimed_until IS NULL OR claimed_until < ?", Time.current) }

  validates :title, presence: true
  validates :state, inclusion: { in: STATES }
  validates :priority, numericality: { greater_than_or_equal_to: 0 }
end
