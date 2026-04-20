class CreateResourceHealths < ActiveRecord::Migration[8.0]
  def change
    create_table :resource_healths, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :resource_key, null: false
      t.datetime :last_failure_at
      t.datetime :cooldown_until
      t.integer :failure_count, null: false, default: 0
      t.text :last_error_message
      t.timestamps
    end

    add_index :resource_healths, [ :workspace_id, :resource_key ], unique: true
    add_index :resource_healths, :cooldown_until
  end
end
