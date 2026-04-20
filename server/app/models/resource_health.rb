class ResourceHealth < ApplicationRecord
  belongs_to :workspace

  scope :on_cooldown, -> { where("cooldown_until > ?", Time.current) }
  scope :recent_first, -> { order(updated_at: :desc) }

  validates :resource_key, presence: true
  validates :resource_key, uniqueness: { scope: :workspace_id }
  validates :failure_count, numericality: { greater_than_or_equal_to: 0 }

  def self.upsert_failure!(workspace:, resource_key:, error_message: nil)
    record = workspace.resource_healths.find_or_initialize_by(resource_key: resource_key)
    record.failure_count = (record.failure_count || 0) + 1
    record.last_failure_at = Time.current
    record.last_error_message = error_message
    record.cooldown_until = backoff_until(record.failure_count)
    record.save!
    record
  end

  def on_cooldown?
    cooldown_until.present? && cooldown_until > Time.current
  end

  private_class_method def self.backoff_until(failure_count)
    backoff_seconds = [ 30 * (2 ** (failure_count - 1)), 3600 ].min
    Time.current + backoff_seconds.seconds
  end
end
