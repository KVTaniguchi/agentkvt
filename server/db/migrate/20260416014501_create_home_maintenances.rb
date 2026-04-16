class CreateHomeMaintenances < ActiveRecord::Migration[8.0]
  def change
    create_table :home_maintenances do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :key_component, null: false
      t.datetime :last_serviced_at, null: false
      t.integer :standard_interval_days, null: false
      t.text :notes

      t.timestamps
    end
  end
end
