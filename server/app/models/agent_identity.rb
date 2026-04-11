class AgentIdentity < ApplicationRecord
  belongs_to :workspace

  validates :display_name, presence: true
  validates :workspace_id, uniqueness: true
end
