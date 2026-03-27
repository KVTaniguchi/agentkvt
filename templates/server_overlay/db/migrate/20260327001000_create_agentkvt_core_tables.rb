class CreateAgentkvtCoreTables < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :uuid do |t|
      t.string :apple_subject, null: false
      t.string :email
      t.string :display_name
      t.timestamps
    end
    add_index :users, :apple_subject, unique: true

    create_table :devices, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :platform, null: false
      t.string :device_name
      t.string :app_version
      t.string :push_token
      t.datetime :last_seen_at
      t.timestamps
    end

    create_table :workspaces, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :server_mode, null: false, default: "single_mac_brain"
      t.timestamps
    end
    add_index :workspaces, :slug, unique: true

    create_table :workspace_memberships, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :role, null: false, default: "member"
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :workspace_memberships, [:workspace_id, :user_id], unique: true

    create_table :family_members, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :device, type: :uuid, foreign_key: true
      t.string :display_name, null: false
      t.string :symbol
      t.string :source, null: false, default: "ios"
      t.timestamps
    end

    create_table :missions, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :owner_profile, type: :uuid, foreign_key: { to_table: :family_members }
      t.references :source_device, type: :uuid, foreign_key: { to_table: :devices }
      t.string :mission_name, null: false
      t.text :system_prompt, null: false
      t.string :trigger_schedule, null: false
      t.jsonb :allowed_mcp_tools, null: false, default: []
      t.boolean :is_enabled, null: false, default: true
      t.datetime :last_run_at
      t.datetime :source_updated_at
      t.timestamps
    end
    add_index :missions, [:workspace_id, :is_enabled]

    create_table :life_context_entries, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :updated_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.string :key, null: false
      t.text :value, null: false
      t.timestamps
    end
    add_index :life_context_entries, [:workspace_id, :key], unique: true

    create_table :action_items, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :source_mission, type: :uuid, foreign_key: { to_table: :missions }
      t.references :owner_profile, type: :uuid, foreign_key: { to_table: :family_members }
      t.string :title, null: false
      t.string :system_intent, null: false
      t.jsonb :payload_json, null: false, default: {}
      t.float :relevance_score, null: false, default: 0.0
      t.boolean :is_handled, null: false, default: false
      t.datetime :handled_at
      t.datetime :timestamp, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.string :created_by, null: false, default: "mac_agent"
      t.timestamps
    end
    add_index :action_items, [:workspace_id, :is_handled, :timestamp]

    create_table :agent_logs, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :mission, type: :uuid, foreign_key: true
      t.string :phase, null: false
      t.text :content, null: false
      t.jsonb :metadata_json, null: false, default: {}
      t.datetime :timestamp, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end
    add_index :agent_logs, [:workspace_id, :timestamp]
  end
end
