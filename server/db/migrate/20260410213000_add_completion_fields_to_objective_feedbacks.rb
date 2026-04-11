class AddCompletionFieldsToObjectiveFeedbacks < ActiveRecord::Migration[8.0]
  def change
    add_column :objective_feedbacks, :completion_summary, :text
    add_column :objective_feedbacks, :completed_at, :datetime
  end
end
