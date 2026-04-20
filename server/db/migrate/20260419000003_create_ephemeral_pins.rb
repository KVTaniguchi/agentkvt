class CreateEphemeralPins < ActiveRecord::Migration[8.0]
  def change
    create_table :ephemeral_pins, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.text :content, null: false
      t.string :category
      t.float :strength, null: false, default: 1.0
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :ephemeral_pins, [ :workspace_id, :expires_at ]
  end
end
