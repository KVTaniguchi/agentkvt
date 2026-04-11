require "rss"
require "open-uri"

# Fetches configured RSS feeds and posts new items to the Slack feed channel.
# Runs on a schedule; uses a publish-time window to avoid duplicates without
# requiring persistent state. Set RSS_FEED_URLS (comma-separated) and
# SLACK_FEED_CHANNEL_IDS (the target channel) in the server .env.
class RssFeedPollerJob < ApplicationJob
  queue_as :background

  LOOKBACK_SECONDS = 20 * 60  # post items published in the last 20 minutes
  FETCH_TIMEOUT    = 15        # seconds per feed

  def perform
    channel_id = feed_channel_id
    unless channel_id
      Rails.logger.warn("[RssFeedPollerJob] SLACK_FEED_CHANNEL_IDS not set — skipping")
      return
    end

    feed_urls.each do |url|
      poll(url, channel_id)
    rescue => e
      Rails.logger.warn("[RssFeedPollerJob] Error polling #{url}: #{e.message}")
    end
  end

  private

  def feed_channel_id
    ENV.fetch("SLACK_FEED_CHANNEL_IDS", "").split(",").map(&:strip).first.presence
  end

  def feed_urls
    ENV.fetch("RSS_FEED_URLS", "").split(",").map(&:strip).reject(&:empty?)
  end

  def poll(url, channel_id)
    cutoff = Time.now - LOOKBACK_SECONDS
    items  = fetch_items(url)
    fresh  = items.select { |item| item_time(item)&.>=(cutoff) }

    Rails.logger.info("[RssFeedPollerJob] #{url} — #{items.size} items, #{fresh.size} fresh")

    fresh.each do |item|
      text = format_item(item)
      next if text.blank?
      Slack::Notifier.call(channel: channel_id, text: text)
    rescue => e
      Rails.logger.warn("[RssFeedPollerJob] Failed to post item from #{url}: #{e.message}")
    end
  end

  def fetch_items(url)
    raw = URI.open(url, read_timeout: FETCH_TIMEOUT, open_timeout: FETCH_TIMEOUT).read
    feed = RSS::Parser.parse(raw, false)
    return [] unless feed

    feed.respond_to?(:items) ? feed.items : feed.entries
  rescue => e
    Rails.logger.warn("[RssFeedPollerJob] Fetch failed for #{url}: #{e.message}")
    []
  end

  def item_time(item)
    t = item.respond_to?(:pubDate) ? item.pubDate : nil
    t ||= item.respond_to?(:published) ? item.published : nil
    t ||= item.respond_to?(:updated) ? item.updated : nil
    t&.to_time
  rescue
    nil
  end

  def format_item(item)
    title = item.respond_to?(:title) ? item.title&.content || item.title : nil
    title = title.to_s.strip
    link  = item.respond_to?(:link) ? item.link&.href || item.link : nil
    link  = link.to_s.strip

    return nil if title.blank?
    link.present? ? "#{title}\n#{link}" : title
  end
end
