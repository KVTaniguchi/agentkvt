class DropActionItemsTable < ActiveRecord::Migration[8.0]
  def up
    drop_table :action_items, if_exists: true
  end

  def down
    create_table :action_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.uuid :owner_profile_id
      t.string :title, null: false
      t.string :system_intent, null: false, default: "reminder.add"
      t.jsonb :payload_json, default: {}
      t.float :relevance_score, default: 1.0
      t.boolean :is_handled, default: false
      t.datetime :handled_at
      t.datetime :timestamp, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.string :created_by
      t.string :content_hash
      t.timestamps
    end
    add_index :action_items, [:workspace_id, :content_hash, :is_handled],
              unique: true,
              where: "is_handled = false",
              name: "index_action_items_on_workspace_content_unhandled"
  end
end
