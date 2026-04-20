class AddExecutionContractToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :task_kind, :string, null: false, default: "research"
    add_column :tasks, :allowed_tool_ids, :jsonb, null: false, default: []
    add_column :tasks, :done_when, :text

    add_index :tasks, :task_kind
    add_index :tasks, :allowed_tool_ids, using: :gin
  end
end
