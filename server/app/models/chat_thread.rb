class ChatThread < ApplicationRecord
  DEFAULT_ALLOWED_TOOL_IDS = [
    "get_life_context",
    "fetch_work_units",
    "read_objective_snapshot",
    "fetch_agent_logs"
  ].freeze
  DEFAULT_SYSTEM_PROMPT = <<~TEXT.squish.freeze
    You are AgentKVT's optional chat assistant. Be concise, helpful, and privacy-conscious.
    When the user asks about objective progress, run status, queued work, or what the Mac agent is doing,
    use the available status tools instead of guessing.
  TEXT

  belongs_to :workspace
  belongs_to :created_by_profile, class_name: "FamilyMember", optional: true
  has_many :chat_messages, dependent: :destroy

  scope :recent_first, -> { order(updated_at: :desc, created_at: :desc) }

  before_validation :apply_defaults

  SYSTEM_PROMPT_MAX_LENGTH = 2000
  INJECTION_PATTERN = /\b(ignore\s+(all\s+)?previous\s+instructions?|system\s+override|act\s+as\s+(if|an?\s+unrestricted)|disregard\s+(all\s+)?prior|you\s+are\s+now\s+(an?\s+)?|forget\s+(all\s+)?previous)/i

  validates :title, presence: true
  validates :system_prompt, presence: true, length: { maximum: SYSTEM_PROMPT_MAX_LENGTH }
  validate :system_prompt_no_injection

  private

  def system_prompt_no_injection
    return if system_prompt.blank?
    if system_prompt.match?(INJECTION_PATTERN)
      errors.add(:system_prompt, "contains disallowed content")
    end
  end

  def apply_defaults
    self.title = title.presence || "Assistant"
    self.system_prompt = system_prompt.presence || DEFAULT_SYSTEM_PROMPT
    self.allowed_tool_ids = DEFAULT_ALLOWED_TOOL_IDS if allowed_tool_ids.blank?
  end
end
