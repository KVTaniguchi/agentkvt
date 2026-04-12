require "rss"
require "open-uri"

# Fetches configured RSS feeds and posts unseen items to the Slack feed channel.
# Deduplicates using Rails.cache keyed on each article's GUID/link (24h TTL).
# Set RSS_FEED_URLS (comma-separated) and SLACK_FEED_CHANNEL_IDS in server .env.
class RssFeedPollerJob < ApplicationJob
  queue_as :background

  FETCH_TIMEOUT = 15  # seconds per feed
  SEEN_TTL      = 24.hours

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
    items = fetch_items(url)
    unseen = items.reject { |item| seen?(item) }

    Rails.logger.info("[RssFeedPollerJob] #{url} — #{items.size} items, #{unseen.size} unseen")

    unseen.each do |item|
      text = format_item(item)
      next if text.blank?
      Slack::Notifier.call(channel: channel_id, text: text)
      mark_seen(item)
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

  def item_guid(item)
    guid = item.respond_to?(:guid) ? item.guid&.content || item.guid.to_s : nil
    guid = item.respond_to?(:id) ? item.id.to_s : nil if guid.blank?
    link = extract_link(item)
    key  = guid.presence || link.presence
    key.presence && "rss_seen:#{Digest::SHA1.hexdigest(key)}"
  end

  def seen?(item)
    key = item_guid(item)
    key ? Rails.cache.exist?(key) : false
  end

  def mark_seen(item)
    key = item_guid(item)
    Rails.cache.write(key, 1, expires_in: SEEN_TTL) if key
  end

  def extract_link(item)
    return nil unless item.respond_to?(:link)
    l = item.link
    l.respond_to?(:href) ? l.href.to_s : l.to_s
  rescue
    nil
  end

  def format_item(item)
    raw   = item.respond_to?(:title) ? item.title : nil
    title = (raw.respond_to?(:content) ? raw.content : raw).to_s.strip
    link  = extract_link(item).to_s.strip

    return nil if title.blank?
    link.present? ? "#{title}\n#{link}" : title
  end
end
