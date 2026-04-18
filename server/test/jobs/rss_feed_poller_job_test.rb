require "test_helper"

class RssFeedPollerJobTest < ActiveSupport::TestCase
  test "perform skips cleanly when rss parser is unavailable" do
    previous_channels = ENV["SLACK_FEED_CHANNEL_IDS"]
    previous_urls = ENV["RSS_FEED_URLS"]
    ENV["SLACK_FEED_CHANNEL_IDS"] = "C123"
    ENV["RSS_FEED_URLS"] = "https://example.com/feed.xml"
    job = RssFeedPollerJob.new

    Slack::Notifier.stub(:call, ->(*) { flunk "should not post when rss is unavailable" }) do
      job.stub(:rss_parser_available?, false) do
        assert_nothing_raised { job.perform }
      end
    end
  ensure
    ENV["SLACK_FEED_CHANNEL_IDS"] = previous_channels
    ENV["RSS_FEED_URLS"] = previous_urls
  end
end
