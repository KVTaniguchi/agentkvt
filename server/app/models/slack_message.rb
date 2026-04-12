class SlackMessage < ApplicationRecord
  INTAKE_KINDS = %w[unknown vendor_app webhook_worker scheduled_feed email_forward user_typed url_unfurl feed_bot].freeze
  TRUST_TIERS = %w[high medium low].freeze

  belongs_to :workspace

  validates :slack_team_id, presence: true
  validates :channel_id, presence: true
  validates :message_ts, presence: true
  validates :intake_kind, inclusion: { in: INTAKE_KINDS }
  validates :trust_tier, inclusion: { in: TRUST_TIERS }
end
