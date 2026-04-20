class CreateInboundEmails < ActiveRecord::Migration[8.0]
  def change
    create_table :inbound_emails, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.string :message_id, null: false
      t.string :inbox_id,   null: false
      t.string :from_address
      t.string :subject
      t.text   :body_text

      t.timestamps
    end

    add_index :inbound_emails, [ :workspace_id, :message_id ], unique: true
  end
end
