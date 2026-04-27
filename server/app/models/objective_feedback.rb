class ObjectiveFeedback < ApplicationRecord
  ROLES = %w[user system].freeze
  FEEDBACK_KINDS = %w[
    follow_up
    compare_options
    challenge_result
    clarify_gaps
    final_recommendation
  ].freeze
  STATUSES = %w[received review_required planned queued completed failed].freeze

  belongs_to :objective
  belongs_to :task, optional: true
  belongs_to :research_snapshot, optional: true
  has_many :objective_feedback_inbound_files, dependent: :destroy
  has_many :inbound_files, through: :objective_feedback_inbound_files
  has_many :follow_up_tasks,
    class_name: "Task",
    foreign_key: :source_feedback_id,
    dependent: :nullify,
    inverse_of: :source_feedback

  scope :recent_first, -> { order(created_at: :desc) }

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :feedback_kind, presence: true, inclusion: { in: FEEDBACK_KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :content, presence: true

  validate :task_belongs_to_objective
  validate :research_snapshot_belongs_to_objective
  validate :snapshot_anchor_matches_task_anchor

  private

  def task_belongs_to_objective
    return if task.blank? || objective.blank?
    return if task.objective_id == objective_id

    errors.add(:task, "must belong to the same objective")
  end

  def research_snapshot_belongs_to_objective
    return if research_snapshot.blank? || objective.blank?
    return if research_snapshot.objective_id == objective_id

    errors.add(:research_snapshot, "must belong to the same objective")
  end

  def snapshot_anchor_matches_task_anchor
    return if research_snapshot.blank? || task.blank?
    return if research_snapshot.task_id.blank? || research_snapshot.task_id == task_id

    errors.add(:research_snapshot, "must match the selected task when both anchors are provided")
  end
end
