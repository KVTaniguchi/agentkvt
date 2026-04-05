class Workspace < ApplicationRecord
  has_many :workspace_memberships, dependent: :destroy
  has_many :users, through: :workspace_memberships
  has_many :family_members, dependent: :destroy
  has_many :life_context_entries, dependent: :destroy
  has_many :action_items, dependent: :destroy
  has_many :agent_logs, dependent: :destroy
  has_many :objectives, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :server_mode, presence: true
end
