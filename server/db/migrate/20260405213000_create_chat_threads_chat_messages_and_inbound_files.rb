class CreateChatThreadsChatMessagesAndInboundFiles < ActiveRecord::Migration[8.0]
  DEFAULT_CHAT_SYSTEM_PROMPT = <<~TEXT.squish.freeze
    You are AgentKVT's optional chat assistant. Be concise, helpful, and privacy-conscious.
    When the user asks about objective progress, run status, queued work, or what the Mac agent is doing,
    use the available status tools instead of guessing.
    When a user asks you to create a concrete follow-up they can act on later, prefer using the
    write_action_item tool if it is available in this chat.
  TEXT

  def change
    create_table :chat_threads, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      t.uuid :created_by_profile_id
      t.string :title, null: false, default: "Assistant"
      t.text :system_prompt, null: false, default: DEFAULT_CHAT_SYSTEM_PROMPT
      t.jsonb :allowed_tool_ids, null: false, default: ["get_life_context", "fetch_work_units"]
      t.timestamps
    end

    add_index :chat_threads, [:workspace_id, :updated_at], name: "index_chat_threads_on_workspace_id_and_updated_at"
    add_foreign_key :chat_threads, :workspaces
    add_foreign_key :chat_threads, :family_members, column: :created_by_profile_id

    create_table :chat_messages, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :chat_thread_id, null: false
      t.uuid :author_profile_id
      t.string :role, null: false
      t.text :content, null: false
      t.string :status, null: false, default: "completed"
      t.text :error_message
      t.datetime :timestamp, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_index :chat_messages, [:chat_thread_id, :timestamp], name: "index_chat_messages_on_chat_thread_id_and_timestamp"
    add_index :chat_messages, [:status, :role, :timestamp], name: "index_chat_messages_on_status_role_and_timestamp"
    add_foreign_key :chat_messages, :chat_threads
    add_foreign_key :chat_messages, :family_members, column: :author_profile_id

    create_table :inbound_files, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      t.uuid :uploaded_by_profile_id
      t.string :file_name, null: false
      t.string :content_type
      t.integer :byte_size, null: false, default: 0
      t.binary :file_data, null: false
      t.datetime :timestamp, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.boolean :is_processed, null: false, default: false
      t.datetime :processed_at
      t.timestamps
    end

    add_index :inbound_files, [:workspace_id, :timestamp], name: "index_inbound_files_on_workspace_id_and_timestamp"
    add_index :inbound_files, [:workspace_id, :is_processed, :timestamp],
              name: "index_inbound_files_on_workspace_processed_timestamp"
    add_foreign_key :inbound_files, :workspaces
    add_foreign_key :inbound_files, :family_members, column: :uploaded_by_profile_id
  end
end
