class CreateObjectiveFeedbacksAndSourceFeedback < ActiveRecord::Migration[8.0]
  def change
    create_table :objective_feedbacks, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :objective, type: :uuid, null: false, foreign_key: true
      t.references :task, type: :uuid, foreign_key: true
      t.references :research_snapshot, type: :uuid, foreign_key: true
      t.string :role, null: false, default: "user"
      t.string :feedback_kind, null: false, default: "follow_up"
      t.string :status, null: false, default: "received"
      t.text :content, null: false
      t.timestamps
    end

    add_index :objective_feedbacks, [ :objective_id, :created_at ]
    add_reference :tasks, :source_feedback, type: :uuid, foreign_key: { to_table: :objective_feedbacks }
  end
end
