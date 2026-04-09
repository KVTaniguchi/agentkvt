class Workspace < ApplicationRecord
  has_many :workspace_memberships, dependent: :destroy
  has_many :users, through: :workspace_memberships
  has_many :family_members, dependent: :destroy
  has_many :chat_threads, dependent: :destroy
  has_many :chat_messages, through: :chat_threads
  has_many :inbound_files, dependent: :destroy
  has_many :life_context_entries, dependent: :destroy
  has_many :action_items, dependent: :destroy
  has_many :agent_logs, dependent: :destroy
  has_many :objectives, dependent: :destroy
  has_many :objective_drafts, dependent: :destroy
  has_many :agent_registrations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :server_mode, presence: true

  def request_chat_wake!
    update!(chat_wake_requested_at: Time.current)
    ActiveRecord::Base.connection.execute("NOTIFY agentkvt_chat_wake")
  end
end
