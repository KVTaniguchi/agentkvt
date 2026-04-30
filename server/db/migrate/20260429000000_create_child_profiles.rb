class CreateChildProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :child_profiles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :family_member_id, null: false
      t.uuid :workspace_id, null: false
      t.string :first_name, null: false
      t.string :last_name
      t.date :date_of_birth, null: false
      t.text :allergies
      t.text :medical_notes
      t.text :dietary_restrictions
      t.string :emergency_contact_name
      t.string :emergency_contact_phone
      t.string :school
      t.string :grade
      t.timestamps
    end

    add_index :child_profiles, :family_member_id, unique: true
    add_index :child_profiles, :workspace_id

    add_foreign_key :child_profiles, :family_members, on_delete: :cascade
    add_foreign_key :child_profiles, :workspaces
  end
end
