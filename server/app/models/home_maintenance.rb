class HomeMaintenance < ApplicationRecord
  belongs_to :workspace

  validates :key_component, presence: true
  validates :last_serviced_at, presence: true
  validates :standard_interval_days, presence: true, numericality: { greater_than: 0 }
end
