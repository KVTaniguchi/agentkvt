class ChatMessage < ApplicationRecord
  ROLES = %w[user assistant system tool].freeze
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :chat_thread, touch: true
  belongs_to :author_profile, class_name: "FamilyMember", optional: true

  scope :chronological, -> { order(timestamp: :asc, created_at: :asc) }
  scope :pending_first, -> { order(timestamp: :asc, created_at: :asc) }

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :content, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
end
