class Mission < ApplicationRecord
  belongs_to :workspace
  belongs_to :owner_profile, class_name: "FamilyMember", optional: true
  belongs_to :source_device, class_name: "Device", optional: true
  has_many :action_items, foreign_key: :source_mission_id, dependent: :nullify, inverse_of: :source_mission
  has_many :agent_logs, dependent: :nullify

  validates :mission_name, presence: true
  validates :system_prompt, presence: true
  validates :trigger_schedule, presence: true

  scope :enabled, -> { where(is_enabled: true) }
  scope :recent_first, -> { order(updated_at: :desc, created_at: :desc) }
end
