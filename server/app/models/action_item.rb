class ActionItem < ApplicationRecord
  belongs_to :workspace
  belongs_to :source_mission, class_name: "Mission", optional: true
  belongs_to :owner_profile, class_name: "FamilyMember", optional: true

  validates :title, presence: true
  validates :system_intent, presence: true

  scope :recent_first, -> { order(timestamp: :desc, created_at: :desc) }
end
