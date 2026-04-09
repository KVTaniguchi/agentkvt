class AddGuidedObjectiveFieldsAndDrafts < ActiveRecord::Migration[8.0]
  def change
    add_column :objectives, :brief_json, :jsonb, null: false, default: {}
    add_column :objectives, :objective_kind, :string
    add_column :objectives, :creation_source, :string, null: false, default: "manual"
    add_index :objectives, [ :workspace_id, :objective_kind ]

    create_table :objective_drafts, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :created_by_profile, type: :uuid, foreign_key: { to_table: :family_members }
      t.references :finalized_objective, type: :uuid, foreign_key: { to_table: :objectives }
      t.string :template_key, null: false, default: "generic"
      t.string :status, null: false, default: "drafting"
      t.jsonb :brief_json, null: false, default: {}
      t.text :suggested_goal
      t.text :assistant_message
      t.jsonb :missing_fields, null: false, default: []
      t.boolean :ready_to_finalize, null: false, default: false
      t.timestamps
    end

    add_index :objective_drafts, [ :workspace_id, :status ]
    add_index :objective_drafts, [ :workspace_id, :created_at ]

    create_table :objective_draft_messages, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :objective_draft, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.datetime :timestamp, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_index :objective_draft_messages,
              [ :objective_draft_id, :timestamp ],
              name: "index_objective_draft_messages_on_draft_and_timestamp"
  end
end
