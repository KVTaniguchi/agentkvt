class ResearchSnapshotFeedback < ApplicationRecord
  ROLES = %w[user].freeze
  RATINGS = %w[good bad].freeze

  belongs_to :workspace
  belongs_to :objective
  belongs_to :research_snapshot
  belongs_to :created_by_profile, class_name: "FamilyMember", optional: true

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :rating, presence: true, inclusion: { in: RATINGS }
  validates :research_snapshot_id, uniqueness: {
    scope: [:created_by_profile_id, :role],
    message: "already has feedback from this viewer"
  }

  validate :objective_matches_snapshot
  validate :workspace_matches_snapshot
  validate :profile_belongs_to_workspace

  scope :recent_first, -> { order(created_at: :desc) }
  scope :good, -> { where(rating: "good") }
  scope :bad, -> { where(rating: "bad") }

  private

  def objective_matches_snapshot
    return if research_snapshot.blank? || objective.blank?
    return if research_snapshot.objective_id == objective_id

    errors.add(:objective, "must match the research snapshot objective")
  end

  def workspace_matches_snapshot
    return if research_snapshot.blank? || workspace.blank?
    return if research_snapshot.objective&.workspace_id == workspace_id

    errors.add(:workspace, "must match the research snapshot workspace")
  end

  def profile_belongs_to_workspace
    return if created_by_profile.blank? || workspace.blank?
    return if created_by_profile.workspace_id == workspace_id

    errors.add(:created_by_profile, "must belong to the same workspace")
  end
end
