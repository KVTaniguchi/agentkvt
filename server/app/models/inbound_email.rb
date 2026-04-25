class InboundEmail < ApplicationRecord
  belongs_to :workspace

  validates :message_id, presence: true
  validates :message_id, uniqueness: { scope: :workspace_id }
end
