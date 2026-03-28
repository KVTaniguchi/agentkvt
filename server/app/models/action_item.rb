class ActionItem < ApplicationRecord
  belongs_to :workspace
  belongs_to :source_mission, class_name: "Mission", optional: true
  belongs_to :owner_profile, class_name: "FamilyMember", optional: true

  validates :title, presence: true
  validates :system_intent, presence: true

  before_validation :compute_content_hash

  scope :recent_first, -> { order(timestamp: :desc, created_at: :desc) }

  # Stable fingerprint for deduplication. Two action items with identical
  # system_intent and payload are considered the same actionable suggestion.
  def self.compute_hash(system_intent, payload_json)
    normalized = if payload_json.present?
      payload_json.sort.map { |k, v| "#{k}=#{v}" }.join(",")
    else
      ""
    end
    Digest::SHA256.hexdigest("#{system_intent}|#{normalized}")
  end

  private

  def compute_content_hash
    self.content_hash = self.class.compute_hash(system_intent, payload_json)
  end
end
