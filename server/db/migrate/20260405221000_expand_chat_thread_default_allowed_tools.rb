# frozen_string_literal: true

class ExpandChatThreadDefaultAllowedTools < ActiveRecord::Migration[8.0]
  OLD_DEFAULT = %w[get_life_context fetch_work_units].freeze
  NEW_DEFAULT = (OLD_DEFAULT + %w[read_objective_snapshot fetch_agent_logs write_action_item]).freeze

  def up
    ChatThread.find_each do |thread|
      ids = thread.allowed_tool_ids
      next unless ids.is_a?(Array) && ids.map(&:to_s).sort == OLD_DEFAULT.sort

      thread.update_column(:allowed_tool_ids, NEW_DEFAULT)
    end

    change_column_default :chat_threads, :allowed_tool_ids, from: OLD_DEFAULT, to: NEW_DEFAULT
  end

  def down
    ChatThread.find_each do |thread|
      ids = thread.allowed_tool_ids
      next unless ids.is_a?(Array) && ids.map(&:to_s).sort == NEW_DEFAULT.sort

      thread.update_column(:allowed_tool_ids, OLD_DEFAULT)
    end

    change_column_default :chat_threads, :allowed_tool_ids, from: NEW_DEFAULT, to: OLD_DEFAULT
  end
end
