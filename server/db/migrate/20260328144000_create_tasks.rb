class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :objective, type: :uuid, null: false, foreign_key: true
      t.text :description, null: false
      t.string :status, null: false, default: "pending"
      t.text :result_summary
      t.timestamps
    end

    add_index :tasks, [ :objective_id, :status ]
  end
end
