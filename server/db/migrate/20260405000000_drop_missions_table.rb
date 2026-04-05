class DropMissionsTable < ActiveRecord::Migration[7.1]
  def change
    remove_reference :action_items, :source_mission, type: :uuid, foreign_key: { to_table: :missions }
    remove_reference :agent_logs, :mission, type: :uuid, foreign_key: true

    drop_table :missions, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.string "mission_name", null: false
      t.text "system_prompt", null: false
      t.string "trigger_schedule", default: "", null: false
      t.jsonb "allowed_mcp_tools", default: [], null: false
      t.uuid "owner_profile_id"
      t.uuid "source_device_id"
      t.uuid "workspace_id", null: false
      t.boolean "is_enabled", default: true, null: false
      t.datetime "last_run_at"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.datetime "run_requested_at"
      t.index ["owner_profile_id"], name: "index_missions_on_owner_profile_id"
      t.index ["source_device_id"], name: "index_missions_on_source_device_id"
      t.index ["workspace_id", "is_enabled"], name: "index_missions_on_workspace_id_and_is_enabled"
      t.index ["workspace_id"], name: "index_missions_on_workspace_id"
    end
  end
end
