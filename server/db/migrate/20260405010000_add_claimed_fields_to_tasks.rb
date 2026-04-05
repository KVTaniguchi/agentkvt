class AddClaimedFieldsToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :claimed_at, :datetime
    add_column :tasks, :claimed_by_agent_id, :string
  end
end
