class ResearchSnapshot < ApplicationRecord
  belongs_to :objective
  belongs_to :task, optional: true
  has_many :anchored_objective_feedbacks, class_name: "ObjectiveFeedback", dependent: :nullify
  has_many :feedback_entries, class_name: "ResearchSnapshotFeedback", dependent: :destroy, inverse_of: :research_snapshot

  SNAPSHOT_KINDS = %w[result exudate].freeze
  scope :repelling, -> { supports_is_repellent? ? where(is_repellent: true) : none }

  def self.supports_snapshot_kind?
    attribute_names.include?("snapshot_kind")
  end

  def self.supports_is_repellent?
    attribute_names.include?("is_repellent")
  end

  def self.supports_repellent_reason?
    attribute_names.include?("repellent_reason")
  end

  def self.supports_repellent_scope?
    attribute_names.include?("repellent_scope")
  end

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

      attrs = {
        value: value,
        task_id: task_id,
        checked_at: checked_at
      }
      attrs[:is_repellent] = is_repellent if supports_is_repellent?
      attrs[:repellent_reason] = repellent_reason if supports_repellent_reason?
      attrs[:repellent_scope] = repellent_scope if supports_repellent_scope?
      attrs[:snapshot_kind] = snapshot_kind if supports_snapshot_kind?

      snapshot.assign_attributes(attrs)
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
  validates :snapshot_kind, inclusion: { in: SNAPSHOT_KINDS }, if: :supports_snapshot_kind?

  validate :value_must_be_plain_language

  scope :recent_first, -> { order(checked_at: :desc) }

  def is_repellent
    has_attribute?("is_repellent") ? ActiveModel::Type::Boolean.new.cast(self[:is_repellent]) : false
  end

  def repellent_reason
    has_attribute?("repellent_reason") ? self[:repellent_reason] : nil
  end

  def repellent_scope
    has_attribute?("repellent_scope") ? self[:repellent_scope] : nil
  end

  def snapshot_kind
    return "result" unless has_attribute?("snapshot_kind")

    self[:snapshot_kind].presence || "result"
  end

  def positive_feedback_count
    feedback_entries.where(rating: "good").count
  end

  def negative_feedback_count
    feedback_entries.where(rating: "bad").count
  end

  private

  def supports_snapshot_kind?
    has_attribute?("snapshot_kind")
  end

  def value_must_be_plain_language
    return if value.blank?
    return if supports_snapshot_kind? && self[:snapshot_kind] == "exudate"

    if ResearchSnapshotValueValidator.json_structure_blob?(value)
      errors.add(:value, "must be plain-language findings, not JSON or structured blobs")
    end
  end
end
