class LifeContextEntry < ApplicationRecord
  belongs_to :workspace
  belongs_to :updated_by_user, class_name: "User", optional: true

  validates :key, presence: true
  validates :key, uniqueness: { scope: :workspace_id }
  validates :value, presence: true
end
