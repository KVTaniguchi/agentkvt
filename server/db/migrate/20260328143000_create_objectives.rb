class CreateObjectives < ActiveRecord::Migration[8.0]
  def change
    create_table :objectives, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.text :goal, null: false
      t.string :status, null: false, default: "pending"
      t.integer :priority, null: false, default: 0
      t.timestamps
    end

    add_index :objectives, [ :workspace_id, :status ]
  end
end
