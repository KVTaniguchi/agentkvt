# frozen_string_literal: true

class AddChatWakeRequestedAtToWorkspaces < ActiveRecord::Migration[8.0]
  def change
    add_column :workspaces, :chat_wake_requested_at, :datetime
  end
end
