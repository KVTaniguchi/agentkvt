class ChatThread < ApplicationRecord
  DEFAULT_ALLOWED_TOOL_IDS = [
    "get_life_context",
    "fetch_work_units",
    "read_objective_snapshot",
    "fetch_agent_logs",
    "write_action_item"
  ].freeze
  DEFAULT_SYSTEM_PROMPT = <<~TEXT.squish.freeze
    You are AgentKVT's optional chat assistant. Be concise, helpful, and privacy-conscious.
    When the user asks about objective progress, run status, queued work, or what the Mac agent is doing,
    use the available status tools instead of guessing.
    When a user asks you to create a concrete follow-up they can act on later, prefer using the
    write_action_item tool if it is available in this chat.
  TEXT

  belongs_to :workspace
  belongs_to :created_by_profile, class_name: "FamilyMember", optional: true
  has_many :chat_messages, dependent: :destroy

  scope :recent_first, -> { order(updated_at: :desc, created_at: :desc) }

  before_validation :apply_defaults

  validates :title, presence: true
  validates :system_prompt, presence: true

  private

  def apply_defaults
    self.title = title.presence || "Assistant"
    self.system_prompt = system_prompt.presence || DEFAULT_SYSTEM_PROMPT
    self.allowed_tool_ids = DEFAULT_ALLOWED_TOOL_IDS if allowed_tool_ids.blank?
  end
end
