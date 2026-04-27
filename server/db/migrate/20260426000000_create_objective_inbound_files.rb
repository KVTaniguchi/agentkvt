class CreateObjectiveInboundFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :objective_inbound_files, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :objective_id, null: false
      t.uuid :inbound_file_id, null: false
      t.timestamps
    end

    add_index :objective_inbound_files, %i[objective_id inbound_file_id], unique: true, name: "index_objective_inbound_files_unique"
    add_index :objective_inbound_files, :inbound_file_id

    add_foreign_key :objective_inbound_files, :objectives
    add_foreign_key :objective_inbound_files, :inbound_files
  end
end
