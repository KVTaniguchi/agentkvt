class CreateObjectiveFeedbackInboundFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :objective_feedback_inbound_files, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :objective_feedback_id, null: false
      t.uuid :inbound_file_id, null: false
      t.timestamps
    end

    add_index :objective_feedback_inbound_files, %i[objective_feedback_id inbound_file_id],
      unique: true,
      name: "index_feedback_inbound_files_unique"
    add_index :objective_feedback_inbound_files, :inbound_file_id

    add_foreign_key :objective_feedback_inbound_files, :objective_feedbacks
    add_foreign_key :objective_feedback_inbound_files, :inbound_files
  end
end
