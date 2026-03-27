class WorkspaceMembership < ApplicationRecord
  belongs_to :workspace
  belongs_to :user

  validates :role, presence: true
  validates :status, presence: true
  validates :user_id, uniqueness: { scope: :workspace_id }
end
