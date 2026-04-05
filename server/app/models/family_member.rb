class FamilyMember < ApplicationRecord
  belongs_to :workspace
  belongs_to :device, optional: true
  has_many :missions, foreign_key: :owner_profile_id, dependent: :nullify, inverse_of: :owner_profile
  has_many :action_items, foreign_key: :owner_profile_id, dependent: :nullify, inverse_of: :owner_profile
  has_many :chat_threads, foreign_key: :created_by_profile_id, dependent: :nullify, inverse_of: :created_by_profile
  has_many :chat_messages, foreign_key: :author_profile_id, dependent: :nullify, inverse_of: :author_profile
  has_many :uploaded_inbound_files, class_name: "InboundFile", foreign_key: :uploaded_by_profile_id,
                                    dependent: :nullify, inverse_of: :uploaded_by_profile

  validates :display_name, presence: true
  validates :source, presence: true
end
