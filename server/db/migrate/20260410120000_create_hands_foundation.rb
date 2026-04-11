class CreateHandsFoundation < ActiveRecord::Migration[8.0]
  def change
    create_table :slack_workspace_links, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.string :slack_team_id, null: false
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :slack_workspace_links, :slack_team_id, unique: true

    create_table :agent_identities, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :display_name, null: false
      t.string :from_email
      t.string :from_name
      t.string :slack_bot_user_id
      t.string :avatar_url
      t.timestamps
    end
    add_index :agent_identities, :workspace_id, unique: true

    create_table :agent_personas, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :channel_type, null: false
      t.text :signature
      t.string :tone
      t.text :intro_bio
      t.timestamps
    end
    add_index :agent_personas, [ :workspace_id, :channel_type ], unique: true

    create_table :workspace_provider_credentials, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :credential_type, null: false, default: "api_credential"
      t.text :secret_value
      t.jsonb :metadata_json, null: false, default: {}
      t.timestamps
    end
    add_index :workspace_provider_credentials, [ :workspace_id, :provider ], unique: true

    create_table :slack_messages, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :slack_team_id, null: false
      t.string :channel_id, null: false
      t.string :message_ts, null: false
      t.string :slack_user_id
      t.text :text
      t.jsonb :raw_payload_json, null: false, default: {}
      t.string :intake_kind, null: false, default: "unknown"
      t.string :trust_tier, null: false, default: "low"
      t.jsonb :provenance_json, null: false, default: {}
      t.timestamps
    end
    add_index :slack_messages,
              [ :workspace_id, :slack_team_id, :channel_id, :message_ts ],
              unique: true,
              name: "index_slack_messages_on_workspace_team_channel_ts"

    add_column :objectives, :hands_config, :jsonb, null: false, default: {}
  end
end
