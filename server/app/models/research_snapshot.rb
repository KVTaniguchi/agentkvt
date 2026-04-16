class ResearchSnapshot < ApplicationRecord
  belongs_to :objective
  belongs_to :task, optional: true
  has_many :anchored_objective_feedbacks, class_name: "ObjectiveFeedback", dependent: :nullify

  def self.upsert_for_objective!(objective:, key:, value:, checked_at: Time.current, task_id: nil, is_repellent: false, repellent_reason: nil, repellent_scope: nil, snapshot_kind: "result")
    attempts = 0

    begin
      snapshot = objective.research_snapshots.find_or_initialize_by(key: key)

      if snapshot.persisted?
        if snapshot.value != value
          snapshot.previous_value = snapshot.value
          snapshot.delta_note = "Changed from #{snapshot.value} to #{value}"
        else
          # Same value: clear any stale delta_note so DeltaMonitorJob doesn't re-alert.
          snapshot.delta_note = nil
        end
      end

      snapshot.assign_attributes(
        value: value,
        is_repellent: is_repellent,
        repellent_reason: repellent_reason,
        repellent_scope: repellent_scope,
        snapshot_kind: snapshot_kind,
        task_id: task_id,
        checked_at: checked_at
      )
      snapshot.save!
      snapshot
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts < 2
      raise
    end
  end

  validates :key, presence: true
  validates :value, presence: true

  SNAPSHOT_KINDS = %w[result exudate].freeze
  validates :snapshot_kind, inclusion: { in: SNAPSHOT_KINDS }

  validate :value_must_be_plain_language

  scope :recent_first, -> { order(checked_at: :desc) }

  private

  def value_must_be_plain_language
    return if value.blank?
    return if snapshot_kind == "exudate"

    if ResearchSnapshotValueValidator.json_structure_blob?(value)
      errors.add(:value, "must be plain-language findings, not JSON or structured blobs")
    end
  end
end
