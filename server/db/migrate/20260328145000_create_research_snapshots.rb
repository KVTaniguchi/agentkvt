class CreateResearchSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :research_snapshots, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :objective, type: :uuid, null: false, foreign_key: true
      t.references :task, type: :uuid, foreign_key: true
      t.string :key, null: false
      t.text :value, null: false
      t.text :previous_value
      t.text :delta_note
      t.datetime :checked_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    # One live snapshot per (objective, key) — upsert by this pair
    add_index :research_snapshots, [ :objective_id, :key ], unique: true
  end
end
