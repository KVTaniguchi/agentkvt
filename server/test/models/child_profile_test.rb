require "test_helper"
require "securerandom"

class ChildProfileTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @family_member = @workspace.family_members.create!(display_name: "Everett", symbol: "E", source: "ios")
  end

  test "valid with required fields" do
    profile = ChildProfile.new(
      workspace: @workspace,
      family_member: @family_member,
      first_name: "Everett",
      last_name: "Taniguchi",
      date_of_birth: Date.new(2018, 6, 15)
    )

    assert profile.valid?
  end

  test "requires first_name and date_of_birth" do
    profile = ChildProfile.new(workspace: @workspace, family_member: @family_member)

    assert_not profile.valid?
    assert_includes profile.errors[:first_name], "can't be blank"
    assert_includes profile.errors[:date_of_birth], "can't be blank"
  end

  test "enforces one profile per family member" do
    ChildProfile.create!(
      workspace: @workspace,
      family_member: @family_member,
      first_name: "Everett",
      date_of_birth: Date.new(2018, 6, 15)
    )

    duplicate = ChildProfile.new(
      workspace: @workspace,
      family_member: @family_member,
      first_name: "Everett",
      date_of_birth: Date.new(2018, 6, 15)
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:family_member_id], "has already been taken"
  end

  test "rejects mismatched workspace" do
    other_workspace = Workspace.create!(name: "Other", slug: "workspace-#{SecureRandom.hex(4)}")
    profile = ChildProfile.new(
      workspace: other_workspace,
      family_member: @family_member,
      first_name: "Everett",
      date_of_birth: Date.new(2018, 6, 15)
    )

    assert_not profile.valid?
    assert_includes profile.errors[:workspace], "must match the family member workspace"
  end

  test "computes age on a given date" do
    profile = ChildProfile.new(date_of_birth: Date.new(2018, 6, 15))

    assert_equal 7, profile.age_on(Date.new(2026, 4, 29))
    assert_equal 7, profile.age_on(Date.new(2026, 6, 14))
    assert_equal 8, profile.age_on(Date.new(2026, 6, 15))
  end

  test "registration payload exposes registration-relevant fields" do
    profile = ChildProfile.create!(
      workspace: @workspace,
      family_member: @family_member,
      first_name: "Everett",
      last_name: "Taniguchi",
      date_of_birth: Date.new(2018, 6, 15),
      allergies: "peanuts",
      emergency_contact_name: "Kevin",
      emergency_contact_phone: "215-555-0100"
    )

    payload = profile.to_registration_payload

    assert_equal "Everett", payload[:first_name]
    assert_equal "2018-06-15", payload[:date_of_birth]
    assert_equal "peanuts", payload[:allergies]
    assert_equal "Kevin", payload[:emergency_contact][:name]
  end
end
