class ResearchSnapshot < ApplicationRecord
  belongs_to :objective
  belongs_to :task, optional: true

  validates :key, presence: true
  validates :value, presence: true
  validate :value_must_be_plain_language

  scope :recent_first, -> { order(checked_at: :desc) }

  private

  def value_must_be_plain_language
    return if value.blank?

    if ResearchSnapshotValueValidator.json_structure_blob?(value)
      errors.add(:value, "must be plain-language findings, not JSON or structured blobs")
    end
  end
end
