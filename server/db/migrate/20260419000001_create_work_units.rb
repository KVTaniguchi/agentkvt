class CreateWorkUnits < ActiveRecord::Migration[8.0]
  def change
    create_table :work_units, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :title, null: false, default: ""
      t.string :category, null: false, default: "general"
      t.uuid :objective_id
      t.uuid :source_task_id
      t.string :work_type, null: false, default: "general"
      t.string :state, null: false, default: "draft"
      t.jsonb :mound_payload, null: false, default: {}
      t.string :active_phase_hint
      t.float :priority, null: false, default: 1.0
      t.datetime :claimed_until
      t.string :worker_label
      t.datetime :last_heartbeat_at
      t.uuid :created_by_profile_id
      t.timestamps
    end

    add_index :work_units, [ :workspace_id, :state ]
    add_index :work_units, :objective_id
  end
end
