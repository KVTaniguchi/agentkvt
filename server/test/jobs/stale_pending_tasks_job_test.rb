require "test_helper"
require "securerandom"

class StalePendingTasksJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Stale WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Research best coffee grinders", status: "active")
  end

  def with_stubbed_notifier
    notify_calls = []
    original_call = Slack::Notifier.method(:call)
    Slack::Notifier.define_singleton_method(:call) { |**args| notify_calls << args }
    yield notify_calls
  ensure
    Slack::Notifier.define_singleton_method(:call, &original_call)
  end

  test "does nothing when SLACK_FEED_CHANNEL_IDS is not set" do
    @objective.tasks.create!(description: "Find top-rated grinders", status: "pending", created_at: 20.minutes.ago)
    stub_env("SLACK_FEED_CHANNEL_IDS", "") do
      with_stubbed_notifier do |notify_calls|
        StalePendingTasksJob.new.perform
        assert_empty notify_calls
      end
    end
  end

  test "does nothing when pending tasks are recent" do
    @objective.tasks.create!(description: "Find top-rated grinders", status: "pending", created_at: 2.minutes.ago)
    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        StalePendingTasksJob.new.perform
        assert_empty notify_calls
      end
    end
  end

  test "does nothing when there are in_progress tasks" do
    @objective.tasks.create!(description: "Find top-rated grinders", status: "pending", created_at: 20.minutes.ago)
    @objective.tasks.create!(description: "Check availability", status: "in_progress", created_at: 5.minutes.ago)
    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        StalePendingTasksJob.new.perform
        assert_empty notify_calls
      end
    end
  end

  test "does nothing for completed or archived objectives" do
    completed = @workspace.objectives.create!(goal: "Done objective", status: "completed")
    completed.tasks.create!(description: "Old task", status: "pending", created_at: 20.minutes.ago)
    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        StalePendingTasksJob.new.perform
        assert_empty notify_calls
      end
    end
  end

  test "alerts when pending tasks are stale and no in_progress tasks" do
    @objective.tasks.create!(description: "Find top-rated grinders", status: "pending", created_at: 20.minutes.ago)
    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        StalePendingTasksJob.new.perform
        assert_equal 1, notify_calls.size
        assert_match(/stalled/i, notify_calls.first[:text])
        assert_match(/coffee grinders/i, notify_calls.first[:text])
      end
    end
  end

  test "does not re-alert within TTL window" do
    @objective.tasks.create!(description: "Find top-rated grinders", status: "pending", created_at: 20.minutes.ago)

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write("stale_pending_tasks:#{@objective.id}", true, expires_in: 30.minutes)

    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        StalePendingTasksJob.new.perform
        assert_empty notify_calls
      end
    end
  ensure
    Rails.cache = original_cache
  end

  private

  def stub_env(key, value, &block)
    original = ENV[key]
    ENV[key] = value
    block.call
  ensure
    ENV[key] = original
  end
end
