class CreateClientContextSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :client_context_snapshots, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.jsonb :location_snapshot, null: false, default: {}
      t.jsonb :weather_snapshot, null: false, default: {}
      t.jsonb :scheduled_events, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end
  end
end
