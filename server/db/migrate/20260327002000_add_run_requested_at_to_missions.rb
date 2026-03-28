class AddRunRequestedAtToMissions < ActiveRecord::Migration[8.0]
  def change
    add_column :missions, :run_requested_at, :datetime
  end
end
