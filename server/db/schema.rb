# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_06_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "action_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "source_mission_id"
    t.uuid "owner_profile_id"
    t.string "title", null: false
    t.string "system_intent", null: false
    t.jsonb "payload_json", default: {}, null: false
    t.float "relevance_score", default: 0.0, null: false
    t.boolean "is_handled", default: false, null: false
    t.datetime "handled_at"
    t.datetime "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "created_by", default: "mac_agent", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "content_hash"
    t.index ["owner_profile_id"], name: "index_action_items_on_owner_profile_id"
    t.index ["source_mission_id"], name: "index_action_items_on_source_mission_id"
    t.index ["workspace_id", "content_hash"], name: "idx_action_items_workspace_content_hash_unhandled", unique: true, where: "(is_handled = false)"
    t.index ["workspace_id", "is_handled", "timestamp"], name: "idx_on_workspace_id_is_handled_timestamp_51f72a0818"
    t.index ["workspace_id"], name: "index_action_items_on_workspace_id"
  end

  create_table "agent_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "mission_id"
    t.string "phase", null: false
    t.text "content", null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.datetime "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mission_id"], name: "index_agent_logs_on_mission_id"
    t.index ["workspace_id", "timestamp"], name: "index_agent_logs_on_workspace_id_and_timestamp"
    t.index ["workspace_id"], name: "index_agent_logs_on_workspace_id"
  end

  create_table "agent_registrations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "agent_id", null: false
    t.string "webhook_url"
    t.jsonb "capabilities", default: [], null: false
    t.string "status", default: "online", null: false
    t.datetime "last_seen_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_agent_registrations_on_capabilities", using: :gin
    t.index ["last_seen_at"], name: "index_agent_registrations_on_last_seen_at"
    t.index ["workspace_id", "agent_id"], name: "index_agent_registrations_on_workspace_id_and_agent_id", unique: true
  end

  create_table "chat_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "chat_thread_id", null: false
    t.uuid "author_profile_id"
    t.string "role", null: false
    t.text "content", null: false
    t.string "status", default: "completed", null: false
    t.text "error_message"
    t.datetime "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_thread_id", "timestamp"], name: "index_chat_messages_on_chat_thread_id_and_timestamp"
    t.index ["status", "role", "timestamp"], name: "index_chat_messages_on_status_role_and_timestamp"
  end

  create_table "chat_threads", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "created_by_profile_id"
    t.string "title", default: "Assistant", null: false
    t.text "system_prompt", default: "You are AgentKVT's optional chat assistant. Be concise, helpful, and privacy-conscious. When the user asks about objective progress, run status, queued work, or what the Mac agent is doing, use the available status tools instead of guessing. When a user asks you to create a concrete follow-up they can act on later, prefer using the write_action_item tool if it is available in this chat.", null: false
    t.jsonb "allowed_tool_ids", default: ["get_life_context", "fetch_work_units", "read_objective_snapshot", "fetch_agent_logs", "write_action_item"], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "updated_at"], name: "index_chat_threads_on_workspace_id_and_updated_at"
  end

  create_table "devices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "platform", null: false
    t.string "device_name"
    t.string "app_version"
    t.string "push_token"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "family_members", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "device_id"
    t.string "display_name", null: false
    t.string "symbol"
    t.string "source", default: "ios", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_family_members_on_device_id"
    t.index ["workspace_id"], name: "index_family_members_on_workspace_id"
  end

  create_table "inbound_files", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "uploaded_by_profile_id"
    t.string "file_name", null: false
    t.string "content_type"
    t.integer "byte_size", default: 0, null: false
    t.binary "file_data", null: false
    t.datetime "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.boolean "is_processed", default: false, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "is_processed", "timestamp"], name: "index_inbound_files_on_workspace_processed_timestamp"
    t.index ["workspace_id", "timestamp"], name: "index_inbound_files_on_workspace_id_and_timestamp"
  end

  create_table "life_context_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "updated_by_user_id"
    t.string "key", null: false
    t.text "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["updated_by_user_id"], name: "index_life_context_entries_on_updated_by_user_id"
    t.index ["workspace_id", "key"], name: "index_life_context_entries_on_workspace_id_and_key", unique: true
    t.index ["workspace_id"], name: "index_life_context_entries_on_workspace_id"
  end

  create_table "objectives", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.text "goal", null: false
    t.string "status", default: "pending", null: false
    t.integer "priority", default: 0, null: false
    t.text "presentation_json"
    t.datetime "presentation_generated_at"
    t.datetime "presentation_enqueued_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "status"], name: "index_objectives_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_objectives_on_workspace_id"
  end

  create_table "research_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "objective_id", null: false
    t.uuid "task_id"
    t.string "key", null: false
    t.text "value", null: false
    t.text "previous_value"
    t.text "delta_note"
    t.datetime "checked_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["objective_id", "key"], name: "index_research_snapshots_on_objective_id_and_key", unique: true
    t.index ["objective_id"], name: "index_research_snapshots_on_objective_id"
    t.index ["task_id"], name: "index_research_snapshots_on_task_id"
  end

  create_table "tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "objective_id", null: false
    t.text "description", null: false
    t.string "status", default: "pending", null: false
    t.text "result_summary"
    t.datetime "claimed_at"
    t.string "claimed_by_agent_id"
    t.jsonb "required_capabilities", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["objective_id", "status"], name: "index_tasks_on_objective_id_and_status"
    t.index ["objective_id"], name: "index_tasks_on_objective_id"
    t.index ["required_capabilities"], name: "index_tasks_on_required_capabilities", using: :gin
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "apple_subject", null: false
    t.string "email"
    t.string "display_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_subject"], name: "index_users_on_apple_subject", unique: true
  end

  create_table "workspace_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "user_id", null: false
    t.string "role", default: "member", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_workspace_memberships_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_workspace_memberships_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_workspace_memberships_on_workspace_id"
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "server_mode", default: "single_mac_brain", null: false
    t.datetime "chat_wake_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "action_items", "family_members", column: "owner_profile_id"
  add_foreign_key "action_items", "workspaces"
  add_foreign_key "agent_logs", "workspaces"
  add_foreign_key "agent_registrations", "workspaces"
  add_foreign_key "chat_messages", "chat_threads"
  add_foreign_key "chat_messages", "family_members", column: "author_profile_id"
  add_foreign_key "chat_threads", "family_members", column: "created_by_profile_id"
  add_foreign_key "chat_threads", "workspaces"
  add_foreign_key "devices", "users"
  add_foreign_key "family_members", "devices"
  add_foreign_key "family_members", "workspaces"
  add_foreign_key "inbound_files", "family_members", column: "uploaded_by_profile_id"
  add_foreign_key "inbound_files", "workspaces"
  add_foreign_key "life_context_entries", "users", column: "updated_by_user_id"
  add_foreign_key "life_context_entries", "workspaces"
  add_foreign_key "objectives", "workspaces"
  add_foreign_key "research_snapshots", "objectives"
  add_foreign_key "research_snapshots", "tasks"
  add_foreign_key "tasks", "objectives"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
end
