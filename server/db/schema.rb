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

ActiveRecord::Schema[8.0].define(version: 2026_04_05_020000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "agent_registrations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid     "workspace_id", null: false
    t.string   "agent_id", null: false
    t.string   "webhook_url"
    t.jsonb    "capabilities", null: false, default: []
    t.string   "status", null: false, default: "online"
    t.datetime "last_seen_at", null: false, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "workspace_id", "agent_id" ], name: "index_agent_registrations_on_workspace_id_and_agent_id", unique: true
    t.index [ "capabilities" ], name: "index_agent_registrations_on_capabilities", using: :gin
    t.index [ "last_seen_at" ], name: "index_agent_registrations_on_last_seen_at"
  end

  create_table "objectives", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.text "goal", null: false
    t.string "status", null: false, default: "pending"
    t.integer "priority", null: false, default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "status"], name: "index_objectives_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_objectives_on_workspace_id"
  end

  create_table "tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "objective_id", null: false
    t.text "description", null: false
    t.string "status", null: false, default: "pending"
    t.text "result_summary"
    t.datetime "claimed_at"
    t.string "claimed_by_agent_id"
    t.jsonb  "required_capabilities", null: false, default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["objective_id", "status"], name: "index_tasks_on_objective_id_and_status"
    t.index ["objective_id"], name: "index_tasks_on_objective_id"
    t.index ["required_capabilities"], name: "index_tasks_on_required_capabilities", using: :gin
  end

  create_table "research_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "objective_id", null: false
    t.uuid "task_id"
    t.string "key", null: false
    t.text "value", null: false
    t.text "previous_value"
    t.text "delta_note"
    t.datetime "checked_at", null: false, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["objective_id", "key"], name: "index_research_snapshots_on_objective_id_and_key", unique: true
    t.index ["objective_id"], name: "index_research_snapshots_on_objective_id"
    t.index ["task_id"], name: "index_research_snapshots_on_task_id"
  end

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

  create_table "missions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "owner_profile_id"
    t.uuid "source_device_id"
    t.string "mission_name", null: false
    t.text "system_prompt", null: false
    t.string "trigger_schedule", null: false
    t.jsonb "allowed_mcp_tools", default: [], null: false
    t.boolean "is_enabled", default: true, null: false
    t.datetime "last_run_at"
    t.datetime "source_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "run_requested_at"
    t.index ["owner_profile_id"], name: "index_missions_on_owner_profile_id"
    t.index ["source_device_id"], name: "index_missions_on_source_device_id"
    t.index ["workspace_id", "is_enabled"], name: "index_missions_on_workspace_id_and_is_enabled"
    t.index ["workspace_id"], name: "index_missions_on_workspace_id"
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

  add_foreign_key "agent_registrations", "workspaces"
  add_foreign_key "action_items", "family_members", column: "owner_profile_id"
  add_foreign_key "action_items", "missions", column: "source_mission_id"
  add_foreign_key "action_items", "workspaces"
  add_foreign_key "agent_logs", "missions"
  add_foreign_key "agent_logs", "workspaces"
  add_foreign_key "devices", "users"
  add_foreign_key "family_members", "devices"
  add_foreign_key "family_members", "workspaces"
  add_foreign_key "life_context_entries", "users", column: "updated_by_user_id"
  add_foreign_key "life_context_entries", "workspaces"
  add_foreign_key "missions", "devices", column: "source_device_id"
  add_foreign_key "missions", "family_members", column: "owner_profile_id"
  add_foreign_key "missions", "workspaces"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
  add_foreign_key "objectives", "workspaces"
  add_foreign_key "tasks", "objectives"
  add_foreign_key "research_snapshots", "objectives"
  add_foreign_key "research_snapshots", "tasks"
end
