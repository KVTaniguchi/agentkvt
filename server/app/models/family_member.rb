class FamilyMember < ApplicationRecord
  belongs_to :workspace
  belongs_to :device, optional: true
  has_many :missions, foreign_key: :owner_profile_id, dependent: :nullify, inverse_of: :owner_profile
  has_many :action_items, foreign_key: :owner_profile_id, dependent: :nullify, inverse_of: :owner_profile

  validates :display_name, presence: true
  validates :source, presence: true
end
