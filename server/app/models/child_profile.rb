class ChildProfile < ApplicationRecord
  belongs_to :family_member
  belongs_to :workspace

  validates :first_name, presence: true
  validates :date_of_birth, presence: true
  validates :family_member_id, uniqueness: true

  validate :workspace_matches_family_member

  def full_name
    [first_name, last_name].compact_blank.join(" ")
  end

  def age_on(date = Date.current)
    return nil unless date_of_birth

    age = date.year - date_of_birth.year
    age -= 1 if date < date_of_birth + age.years
    age
  end

  def to_registration_payload
    {
      first_name: first_name,
      last_name: last_name,
      date_of_birth: date_of_birth&.iso8601,
      age: age_on,
      allergies: allergies,
      medical_notes: medical_notes,
      dietary_restrictions: dietary_restrictions,
      emergency_contact: {
        name: emergency_contact_name,
        phone: emergency_contact_phone
      },
      school: school,
      grade: grade
    }
  end

  private

  def workspace_matches_family_member
    return unless family_member && workspace_id

    if family_member.workspace_id != workspace_id
      errors.add(:workspace, "must match the family member workspace")
    end
  end
end
