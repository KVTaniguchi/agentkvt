class AddBioSignalsToAgentKvt < ActiveRecord::Migration[8.0]
  def change
    add_column :objectives, :nutrient_density, :integer, default: 0, null: false
    
    add_column :research_snapshots, :is_repellent, :boolean, default: false, null: false
    add_column :research_snapshots, :repellent_reason, :text
    add_column :research_snapshots, :repellent_scope, :string
    add_column :research_snapshots, :snapshot_kind, :string, default: "result", null: false
    
    add_index :research_snapshots, [:objective_id, :is_repellent], name: "index_research_snapshots_on_objective_id_and_is_repellent"
  end
end
