class User < ApplicationRecord
  has_many :devices, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships
  has_many :life_context_entries, foreign_key: :updated_by_user_id, dependent: :nullify, inverse_of: :updated_by_user

  validates :apple_subject, presence: true, uniqueness: true
end
