class EphemeralPin < ApplicationRecord
  belongs_to :workspace

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :recent_first, -> { order(created_at: :desc) }

  validates :content, presence: true
  validates :strength, numericality: { greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true
end
