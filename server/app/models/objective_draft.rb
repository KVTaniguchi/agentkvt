class ObjectiveDraft < ApplicationRecord
  STATUSES = %w[drafting finalized].freeze
  STALE_AFTER = 7.days

  belongs_to :workspace
  belongs_to :created_by_profile, class_name: "FamilyMember", optional: true
  belongs_to :finalized_objective, class_name: "Objective", optional: true
  has_many :objective_draft_messages, dependent: :destroy

  scope :chronological, -> { order(created_at: :asc) }
  scope :stale_unfinalized, -> { where.not(status: "finalized").where("created_at < ?", STALE_AFTER.ago) }

  before_validation :normalize_fields

  validates :template_key, presence: true, inclusion: { in: ObjectiveComposerTemplates::TEMPLATE_KEYS }
  validates :status, presence: true, inclusion: { in: STATUSES }

  def planner_summary(goal: nil)
    ObjectivePlanningInputBuilder.for_draft(self, goal: goal)
  end

  private

  def normalize_fields
    self.template_key = ObjectiveComposerTemplates.normalize_template_key(template_key)
    self.status = status.to_s.strip.presence || "drafting"
    self.brief_json = ObjectivePlanningInputBuilder.normalize_brief(brief_json)
    self.missing_fields = Array(missing_fields)
      .map(&:to_s)
      .map(&:strip)
      .select { |field| ObjectiveComposerTemplates::FIELD_KEYS.include?(field) }
      .uniq
  end
end
