class AddPresentationEnqueuedAtToObjectives < ActiveRecord::Migration[8.0]
  def change
    add_column :objectives, :presentation_enqueued_at, :datetime
  end
end
