class CreateAgentRegistrations < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_registrations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid   :workspace_id, null: false
      t.string :agent_id, null: false
      t.string :webhook_url
      t.jsonb  :capabilities, null: false, default: []
      t.string :status, null: false, default: "online"
      t.datetime :last_seen_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_index :agent_registrations, [ :workspace_id, :agent_id ], unique: true
    add_index :agent_registrations, :capabilities, using: :gin
    add_index :agent_registrations, :last_seen_at

    add_foreign_key :agent_registrations, :workspaces

    # Add required_capabilities to tasks (empty = any agent can process)
    add_column :tasks, :required_capabilities, :jsonb, null: false, default: []
    add_index :tasks, :required_capabilities, using: :gin
  end
end
