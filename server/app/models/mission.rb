class Mission < ApplicationRecord
  belongs_to :workspace
  belongs_to :owner_profile, class_name: "FamilyMember", optional: true
  belongs_to :source_device, class_name: "Device", optional: true
  has_many :action_items, foreign_key: :source_mission_id, dependent: :nullify, inverse_of: :source_mission
  has_many :agent_logs, dependent: :nullify

  validates :mission_name, presence: true
  validates :system_prompt, presence: true
  validates :trigger_schedule, presence: true
  validate :prompt_references_write_action_item_if_required

  scope :enabled, -> { where(is_enabled: true) }
  scope :recent_first, -> { order(updated_at: :desc, created_at: :desc) }

  private

  def prompt_references_write_action_item_if_required
    return unless Array(allowed_mcp_tools).include?("write_action_item")
    return if system_prompt.to_s.include?("write_action_item")

    errors.add(:system_prompt, "should mention write_action_item since it is in allowed_mcp_tools — without it the agent may produce no visible output on iOS")
  end
end
