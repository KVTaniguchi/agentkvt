class Device < ApplicationRecord
  belongs_to :user
  has_many :family_members, dependent: :nullify
  has_many :missions, foreign_key: :source_device_id, dependent: :nullify, inverse_of: :source_device

  validates :platform, presence: true
end
