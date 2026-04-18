require "test_helper"

class ResearchSnapshotTest < ActiveSupport::TestCase
  test "bio-signal readers fall back when optional columns are unavailable" do
    snapshot = ResearchSnapshot.new(key: "summary", value: "plain language finding")

    snapshot.define_singleton_method(:has_attribute?) do |name|
      return false if %w[is_repellent repellent_reason repellent_scope snapshot_kind].include?(name)

      super(name)
    end

    assert_equal false, snapshot.is_repellent
    assert_nil snapshot.repellent_reason
    assert_nil snapshot.repellent_scope
    assert_equal "result", snapshot.snapshot_kind
  end
end
