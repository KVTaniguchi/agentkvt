class ResearchSnapshot < ApplicationRecord
  belongs_to :objective
  belongs_to :task, optional: true

  validates :key, presence: true
  validates :value, presence: true
  validate :value_not_raw_tool_json

  scope :recent_first, -> { order(checked_at: :desc) }

  private

  def value_not_raw_tool_json
    return if value.blank?

    if ResearchSnapshotValueValidator.tool_like_json?(value)
      errors.add(:value, "must be plain-language findings, not raw tool-call JSON")
    end
  end
end
