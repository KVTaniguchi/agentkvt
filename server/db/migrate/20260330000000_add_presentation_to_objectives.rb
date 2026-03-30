class AddPresentationToObjectives < ActiveRecord::Migration[8.0]
  def change
    add_column :objectives, :presentation_json, :text
    add_column :objectives, :presentation_generated_at, :datetime
  end
end
