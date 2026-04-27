require "test_helper"
require "securerandom"

class DeltaMonitorJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Delta WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Monitor price changes", status: "active")
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
    stub_env("SLACK_FEED_CHANNEL_IDS", "") do
      with_stubbed_notifier do |notify_calls|
        DeltaMonitorJob.new.perform
        assert_empty notify_calls
      end
    end
  end

  test "notifies about recently changed snapshots" do
    @objective.research_snapshots.create!(
      key: "price",
      value: "Now $45",
      delta_note: "Changed from $50 to $45",
      checked_at: 30.minutes.ago
    )

    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        DeltaMonitorJob.new.perform
        assert_equal 1, notify_calls.size
        assert_match(/price/i, notify_calls.first[:text])
      end
    end
  end

  test "skips snapshots without delta_note" do
    @objective.research_snapshots.create!(
      key: "status",
      value: "Still active",
      delta_note: nil,
      checked_at: 30.minutes.ago
    )

    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        DeltaMonitorJob.new.perform
        assert_empty notify_calls
      end
    end
  end

  test "skips snapshots older than MAX_AGE" do
    @objective.research_snapshots.create!(
      key: "old_price",
      value: "Was $100",
      delta_note: "Changed long ago",
      checked_at: 3.hours.ago
    )

    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        DeltaMonitorJob.new.perform
        assert_empty notify_calls
      end
    end
  end

  test "does not re-alert for already cached snapshots" do
    snapshot = @objective.research_snapshots.create!(
      key: "price",
      value: "Now $45",
      delta_note: "Changed",
      checked_at: 30.minutes.ago
    )

    # test env uses null_store — swap in a real MemoryStore so the cache check works
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    cache_key = "delta_monitor:#{snapshot.id}:#{snapshot.updated_at.to_i}"
    Rails.cache.write(cache_key, true, expires_in: 24.hours)

    stub_env("SLACK_FEED_CHANNEL_IDS", "C123") do
      with_stubbed_notifier do |notify_calls|
        DeltaMonitorJob.new.perform
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
