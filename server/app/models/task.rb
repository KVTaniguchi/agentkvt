class Task < ApplicationRecord
  belongs_to :objective
  belongs_to :source_feedback, class_name: "ObjectiveFeedback", optional: true
  has_many :research_snapshots, dependent: :nullify
  has_many :anchored_objective_feedbacks, class_name: "ObjectiveFeedback", dependent: :nullify

  STATUSES = %w[proposed pending in_progress completed failed].freeze

  validates :description, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending_first, -> { order(created_at: :asc) }
  scope :proposed, -> { where(status: "proposed") }
  scope :initial_plan, -> { where(source_feedback_id: nil) }
  scope :follow_up, -> { where.not(source_feedback_id: nil) }
end
