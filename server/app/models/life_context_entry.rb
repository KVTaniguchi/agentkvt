class LifeContextEntry < ApplicationRecord
  belongs_to :workspace
  belongs_to :updated_by_user, class_name: "User", optional: true

  validates :key, presence: true
  validates :value, presence: true
end
