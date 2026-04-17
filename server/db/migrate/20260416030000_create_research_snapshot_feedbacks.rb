class CreateResearchSnapshotFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :research_snapshot_feedbacks, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :objective, null: false, type: :uuid, foreign_key: true
      t.references :research_snapshot, null: false, type: :uuid, foreign_key: true
      t.references :created_by_profile, type: :uuid, foreign_key: { to_table: :family_members }
      t.string :role, null: false, default: "user"
      t.string :rating, null: false
      t.text :reason
      t.timestamps
    end

    add_index :research_snapshot_feedbacks,
      "research_snapshot_id, role, COALESCE(created_by_profile_id::text, 'anonymous')",
      unique: true,
      name: "index_research_snapshot_feedbacks_on_snapshot_viewer_role"
  end
end
