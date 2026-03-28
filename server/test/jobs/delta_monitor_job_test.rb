require "test_helper"
require "securerandom"

class DeltaMonitorJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective = @workspace.objectives.create!(goal: "Track mortgage rates", status: "active")
  end

  test "creates an ActionItem for a snapshot with a recent delta_note" do
    @objective.research_snapshots.create!(
      key: "30yr_rate",
      value: "7.10%",
      previous_value: "6.85%",
      delta_note: "Changed from 6.85% to 7.10%",
      checked_at: 30.minutes.ago
    )

    assert_difference -> { @workspace.action_items.count }, +1 do
      DeltaMonitorJob.new.perform
    end

    item = @workspace.action_items.last
    assert_equal "research.update",          item.system_intent
    assert_equal "delta_monitor",            item.created_by
    assert_match /30yr_rate/,                item.title
    assert_equal "7.10%",                   item.payload_json["current_value"]
    assert_equal "6.85%",                   item.payload_json["previous_value"]
    assert_equal "Changed from 6.85% to 7.10%", item.payload_json["delta_note"]
  end

  test "ignores snapshots with no delta_note" do
    @objective.research_snapshots.create!(
      key: "30yr_rate",
      value: "6.85%",
      delta_note: nil,
      checked_at: 30.minutes.ago
    )

    assert_no_difference -> { @workspace.action_items.count } do
      DeltaMonitorJob.new.perform
    end
  end

  test "ignores snapshots older than 2 hours" do
    @objective.research_snapshots.create!(
      key: "30yr_rate",
      value: "7.10%",
      previous_value: "6.85%",
      delta_note: "Changed from 6.85% to 7.10%",
      checked_at: 3.hours.ago
    )

    assert_no_difference -> { @workspace.action_items.count } do
      DeltaMonitorJob.new.perform
    end
  end

  test "does not create duplicate ActionItem for the same snapshot on re-run" do
    @objective.research_snapshots.create!(
      key: "30yr_rate",
      value: "7.10%",
      previous_value: "6.85%",
      delta_note: "Changed from 6.85% to 7.10%",
      checked_at: 30.minutes.ago
    )

    DeltaMonitorJob.new.perform
    assert_equal 1, @workspace.action_items.count

    # Duplicate is silently swallowed by the RecordNotUnique rescue
    assert_no_difference -> { @workspace.action_items.count } do
      DeltaMonitorJob.new.perform
    end
  end

  test "processes multiple snapshots from different objectives" do
    objective2 = @workspace.objectives.create!(goal: "Track gas prices", status: "active")

    @objective.research_snapshots.create!(
      key: "30yr_rate", value: "7.10%", previous_value: "6.85%",
      delta_note: "Changed from 6.85% to 7.10%", checked_at: 30.minutes.ago
    )
    objective2.research_snapshots.create!(
      key: "gas_price", value: "$4.10", previous_value: "$3.90",
      delta_note: "Changed from $3.90 to $4.10", checked_at: 45.minutes.ago
    )

    assert_difference -> { @workspace.action_items.count }, +2 do
      DeltaMonitorJob.new.perform
    end
  end

  test "skips snapshot whose workspace cannot be determined" do
    # Orphaned objective (workspace nil via dependent: :destroy — simulate by deleting workspace after)
    other_workspace = Workspace.create!(name: "Temp", slug: "temp-#{SecureRandom.hex(4)}")
    other_obj = other_workspace.objectives.create!(goal: "Temp goal", status: "active")
    other_obj.research_snapshots.create!(
      key: "key", value: "new", previous_value: "old",
      delta_note: "Changed from old to new", checked_at: 30.minutes.ago
    )
    other_workspace.destroy

    # No ActionItem should be created (snapshot's objective was destroyed)
    assert_no_difference -> { ActionItem.count } do
      DeltaMonitorJob.new.perform
    end
  end
end
