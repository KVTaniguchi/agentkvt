class InboundFile < ApplicationRecord
  belongs_to :workspace
  belongs_to :uploaded_by_profile, class_name: "FamilyMember", optional: true
  has_many :objective_inbound_files, dependent: :destroy
  has_many :objectives, through: :objective_inbound_files

  scope :recent_first, -> { order(timestamp: :desc, created_at: :desc) }

  before_validation :sync_byte_size

  validates :file_name, presence: true
  validates :file_data, presence: true
  validates :byte_size, numericality: { greater_than_or_equal_to: 0 }

  private

  def sync_byte_size
    self.byte_size = file_data.to_s.bytesize
  end
end
