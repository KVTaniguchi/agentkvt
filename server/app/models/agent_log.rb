class AgentLog < ApplicationRecord
  belongs_to :workspace
  belongs_to :mission, optional: true

  validates :phase, presence: true
  validates :content, presence: true

  scope :recent_first, -> { order(timestamp: :desc, created_at: :desc) }
  scope :by_phases, ->(phases) { where(phase: phases) }
  scope :since, ->(timestamp) { where("timestamp >= ?", timestamp) }
  scope :by_objective, ->(id) { where("metadata_json ->> 'objective_id' = ?", id.to_s) }
  scope :by_task, ->(id) { where("metadata_json ->> 'task_id' = ?", id.to_s) }
  scope :by_tool, ->(name) { where("metadata_json ->> 'tool_name' = ?", name.to_s) }
end
