class Task < ApplicationRecord
  OBJECTIVE_BASE_TOOL_IDS = %w[
    read_objective_snapshot
    write_objective_snapshot
    list_dropzone_files
    read_dropzone_file
  ].freeze
  RESEARCH_TOOL_IDS = (OBJECTIVE_BASE_TOOL_IDS + %w[multi_step_search]).freeze
  TASK_KINDS = %w[research action synthesis].freeze
  OBJECTIVE_EXECUTION_CAPABILITY = "objective_research".freeze
  TOOL_CAPABILITY_MAP = {
    "multi_step_search" => "web_search",
    "site_scout" => "site_scout",
    "send_notification_email" => "email",
    "write_reminder" => "reminders",
    "read_calendar" => "calendar",
    "github_agent" => "github",
    "read_local_file" => "local_file_read",
    "run_shell_command" => "shell_diagnostics",
    "get_life_context" => "life_context",
    "fetch_bee_ai_context" => "life_context"
  }.freeze

  belongs_to :objective
  belongs_to :source_feedback, class_name: "ObjectiveFeedback", optional: true
  has_many :research_snapshots, dependent: :nullify
  has_many :anchored_objective_feedbacks, class_name: "ObjectiveFeedback", dependent: :nullify

  STATUSES = %w[proposed pending in_progress completed failed].freeze

  before_validation :apply_default_execution_contract, on: :create
  before_validation :normalize_execution_contract

  validates :description, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :task_kind, inclusion: { in: TASK_KINDS }
  validate :allowed_tool_ids_must_be_array
  validate :required_capabilities_must_be_array

  scope :pending_first, -> { order(created_at: :asc) }
  scope :proposed, -> { where(status: "proposed") }
  scope :initial_plan, -> { where(source_feedback_id: nil) }
  scope :follow_up, -> { where.not(source_feedback_id: nil) }

  class << self
    def execution_contract(description:, task_kind: nil, allowed_tool_ids: nil, required_capabilities: nil, done_when: nil)
      normalized_description = description.to_s.strip
      kind = normalized_task_kind(task_kind.presence || inferred_task_kind(normalized_description))
      tool_ids = normalize_allowed_tool_ids(
        allowed_tool_ids,
        task_kind: kind,
        description: normalized_description
      )
      {
        task_kind: kind,
        allowed_tool_ids: tool_ids,
        required_capabilities: normalize_required_capabilities(
          required_capabilities.presence || default_required_capabilities(tool_ids)
        ),
        done_when: normalized_done_when(done_when.presence || default_done_when(kind))
      }
    end

    def normalized_task_kind(value)
      kind = value.to_s.strip.downcase
      TASK_KINDS.include?(kind) ? kind : "research"
    end

    def inferred_task_kind(description)
      normalized = description.to_s.downcase

      return "action" if normalized.match?(
        /\b(site_scout|site scout|add to cart|checkout|pickup|reserve|reservation|book|buy|purchase|order|submit|fill out|click|navigate|log in|login|send email|notify|notification|alert|create reminder|reminder|schedule)\b/
      )

      return "synthesis" if normalized.match?(
        /\b(final recommendation|recommendation|recommend next move|working brief|summary|summarize|summarise|synthesize|synthesise|decision memo|clarify objective scope|success criteria|execution checklist)\b/
      )

      "research"
    end

    def normalize_allowed_tool_ids(ids, task_kind:, description:)
      normalized = Array(ids)
        .flatten
        .map(&:to_s)
        .map(&:strip)
        .reject(&:blank?)

      normalized = default_allowed_tool_ids(task_kind, description) if normalized.empty?
      (OBJECTIVE_BASE_TOOL_IDS + normalized).uniq
    end

    def default_allowed_tool_ids(task_kind, description)
      case task_kind
      when "action"
        ids = OBJECTIVE_BASE_TOOL_IDS + inferred_action_tool_ids(description)
        ids << "multi_step_search" if description.to_s.match?(/\b(verify|confirm|price|availability|hours|current|latest)\b/i)
        ids.uniq
      else
        RESEARCH_TOOL_IDS
      end
    end

    def inferred_action_tool_ids(description)
      normalized = description.to_s.downcase
      ids = []
      ids << "site_scout" if normalized.match?(
        /\b(site_scout|site scout|browser|website|web site|web form|cart|checkout|pickup|reserve|reservation|book|buy|purchase|order|submit|fill out|click|navigate|log in|login)\b/
      )
      ids << "send_notification_email" if normalized.match?(/\b(email|notify|notification|alert)\b/)
      ids << "write_reminder" if normalized.match?(/\b(remind|reminder|follow up later|follow-up later)\b/)
      ids << "read_calendar" if normalized.match?(/\b(calendar|availability|schedule)\b/)
      ids << "github_agent" if normalized.match?(/\b(github|repository|repo|pull request|issue)\b/)
      ids << "read_local_file" if normalized.match?(/\b(local file|read file|document|pdf)\b/)
      ids << "run_shell_command" if normalized.match?(/\b(disk usage|disk space|uptime|memory usage|system diagnostic|brew outdated)\b/)
      ids << "get_life_context" if normalized.match?(/\b(life context|personal context|bee ai|bee)\b/)
      ids.presence || ["site_scout"]
    end

    def default_required_capabilities(tool_ids)
      ([OBJECTIVE_EXECUTION_CAPABILITY] + Array(tool_ids).filter_map { |tool_id| TOOL_CAPABILITY_MAP[tool_id] }).uniq
    end

    def normalize_required_capabilities(ids)
      ([OBJECTIVE_EXECUTION_CAPABILITY] + Array(ids))
        .flatten
        .map(&:to_s)
        .map(&:strip)
        .reject(&:blank?)
        .uniq
    end

    def default_done_when(task_kind)
      case task_kind
      when "action"
        "Attempt the requested action with the allowed tools, verify the outcome, and record a receipt or blocker in an objective snapshot."
      when "synthesis"
        "Write a final objective snapshot that captures the decision, recommendation, or working brief and marks the task complete."
      else
        "Record one or more concrete findings for this task in objective snapshots with enough detail to guide the next step."
      end
    end

    def normalized_done_when(value)
      value.to_s.strip.presence
    end
  end

  private

  def apply_default_execution_contract
    contract = self.class.execution_contract(
      description: description,
      task_kind: task_kind,
      allowed_tool_ids: allowed_tool_ids,
      required_capabilities: required_capabilities,
      done_when: done_when
    )

    self.task_kind = contract[:task_kind]
    self.allowed_tool_ids = contract[:allowed_tool_ids]
    self.required_capabilities = contract[:required_capabilities]
    self.done_when = contract[:done_when]
  end

  def normalize_execution_contract
    self.task_kind = self.class.normalized_task_kind(task_kind.presence || self.class.inferred_task_kind(description))
    self.allowed_tool_ids = self.class.normalize_allowed_tool_ids(
      allowed_tool_ids,
      task_kind: task_kind,
      description: description
    )
    self.required_capabilities = self.class.normalize_required_capabilities(
      required_capabilities.presence || self.class.default_required_capabilities(allowed_tool_ids)
    )
    self.done_when = self.class.normalized_done_when(
      done_when.presence || self.class.default_done_when(task_kind)
    )
  end

  def allowed_tool_ids_must_be_array
    errors.add(:allowed_tool_ids, "must be an array") unless allowed_tool_ids.is_a?(Array)
  end

  def required_capabilities_must_be_array
    errors.add(:required_capabilities, "must be an array") unless required_capabilities.is_a?(Array)
  end
end
