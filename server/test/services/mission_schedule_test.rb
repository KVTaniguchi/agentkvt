require "test_helper"
require "securerandom"

class MissionScheduleTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  test "daily schedules with leading-zero hours are due at the expected time" do
    mission = @workspace.missions.create!(
      mission_name: "Morning Check-In",
      system_prompt: "Create one action item.",
      trigger_schedule: "daily|08:05",
      allowed_mcp_tools: ["write_action_item"],
      is_enabled: true
    )

    at = Time.iso8601("2026-03-27T08:05:00Z")

    assert_equal "2026-03-27T08:05:00Z", MissionSchedule.scheduled_window_start(mission.trigger_schedule, at: at)&.iso8601
    assert MissionSchedule.due?(mission, at: at)
  end
end
