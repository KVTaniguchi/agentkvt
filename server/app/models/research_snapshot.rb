class ResearchSnapshot < ApplicationRecord
  belongs_to :objective
  belongs_to :task, optional: true

  validates :key, presence: true
  validates :value, presence: true

  scope :recent_first, -> { order(checked_at: :desc) }
end
