class ClientContextSnapshot < ApplicationRecord
  belongs_to :workspace

  validates :location_snapshot, presence: true
  validates :weather_snapshot, presence: true
  validates :scheduled_events, presence: true
  validates :raw_payload, presence: true
end
