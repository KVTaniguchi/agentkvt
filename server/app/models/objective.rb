class Objective < ApplicationRecord
  CREATION_SOURCES = %w[manual guided].freeze

  belongs_to :workspace
  has_many :tasks, dependent: :destroy
  has_many :research_snapshots, dependent: :destroy
  has_many :objective_feedbacks, dependent: :destroy

  STATUSES = %w[pending active completed archived].freeze

  before_validation :normalize_guided_fields
  before_validation :normalize_hands_config

  validates :goal, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :creation_source, inclusion: { in: CREATION_SOURCES }
  validates :objective_kind, inclusion: { in: ObjectiveComposerTemplates::TEMPLATE_KEYS }, allow_blank: true

  scope :recent_first, -> { order(priority: :desc, created_at: :desc) }

  private

  def normalize_guided_fields
    self.creation_source = creation_source.to_s.strip.presence || "manual"
    self.objective_kind = objective_kind.to_s.strip.presence
    self.brief_json = ObjectivePlanningInputBuilder.normalize_brief(brief_json)
  end

  def normalize_hands_config
    self.hands_config = {} unless hands_config.is_a?(Hash)
  end
end
