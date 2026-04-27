require "test_helper"

class ObjectiveComposerTemplatesTest < ActiveSupport::TestCase
  # --- normalize_template_key ---

  test "returns key unchanged for valid keys" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      assert_equal key, ObjectiveComposerTemplates.normalize_template_key(key)
    end
  end

  test "returns generic for unknown key" do
    assert_equal "generic", ObjectiveComposerTemplates.normalize_template_key("made_up")
  end

  test "returns generic for nil" do
    assert_equal "generic", ObjectiveComposerTemplates.normalize_template_key(nil)
  end

  test "returns generic for empty string" do
    assert_equal "generic", ObjectiveComposerTemplates.normalize_template_key("")
  end

  test "strips whitespace before normalizing" do
    assert_equal "shopping", ObjectiveComposerTemplates.normalize_template_key("  shopping  ")
  end

  # --- title_for ---

  test "returns correct title for each key" do
    assert_equal "Custom Objective", ObjectiveComposerTemplates.title_for("generic")
    assert_equal "Shopping", ObjectiveComposerTemplates.title_for("shopping")
    assert_equal "Trip Planning", ObjectiveComposerTemplates.title_for("trip_planning")
    assert_equal "Date Night", ObjectiveComposerTemplates.title_for("date_night")
    assert_equal "Budget", ObjectiveComposerTemplates.title_for("budget")
    assert_equal "Household Planning", ObjectiveComposerTemplates.title_for("household_planning")
    assert_equal "Restaurant Reservation", ObjectiveComposerTemplates.title_for("restaurant_reservation")
  end

  test "returns Custom Objective for unknown key" do
    assert_equal "Custom Objective", ObjectiveComposerTemplates.title_for("bogus")
  end

  # --- guidance_for ---

  test "returns a non-empty string for every key" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      guidance = ObjectiveComposerTemplates.guidance_for(key)
      assert guidance.is_a?(String), "Expected String for key #{key}"
      assert guidance.present?, "Expected non-empty guidance for key #{key}"
    end
  end

  test "returns generic guidance for unknown key" do
    generic_guidance = ObjectiveComposerTemplates.guidance_for("generic")
    assert_equal generic_guidance, ObjectiveComposerTemplates.guidance_for("unknown_key")
  end

  # --- required_fields_for ---

  test "returns array for every template key" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      fields = ObjectiveComposerTemplates.required_fields_for(key)
      assert fields.is_a?(Array), "Expected Array for key #{key}"
      assert fields.any?, "Expected non-empty required fields for #{key}"
    end
  end

  test "all required fields are valid FIELD_KEYS" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      fields = ObjectiveComposerTemplates.required_fields_for(key)
      fields.each do |field|
        assert_includes ObjectiveComposerTemplates::FIELD_KEYS, field,
          "#{field} in required_fields_for(#{key}) is not a valid FIELD_KEY"
      end
    end
  end

  test "returns generic required fields for unknown key" do
    generic_fields = ObjectiveComposerTemplates.required_fields_for("generic")
    assert_equal generic_fields, ObjectiveComposerTemplates.required_fields_for("unknown")
  end

  # --- Constants completeness ---

  test "TEMPLATE_TITLES covers all TEMPLATE_KEYS" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      assert ObjectiveComposerTemplates::TEMPLATE_TITLES.key?(key), "Missing title for #{key}"
    end
  end

  test "TEMPLATE_GUIDANCE covers all TEMPLATE_KEYS" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      assert ObjectiveComposerTemplates::TEMPLATE_GUIDANCE.key?(key), "Missing guidance for #{key}"
    end
  end

  test "REQUIRED_FIELDS covers all TEMPLATE_KEYS" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      assert ObjectiveComposerTemplates::REQUIRED_FIELDS.key?(key), "Missing required fields for #{key}"
    end
  end
end
