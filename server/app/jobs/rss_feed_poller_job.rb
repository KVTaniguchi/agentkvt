require "set"
require "open-uri"

# Fetches configured RSS feeds and posts unseen items to the Slack feed channel.
# Deduplicates using Rails.cache keyed on each article's GUID/link (24h TTL).
# Set RSS_FEED_URLS (comma-separated) and SLACK_FEED_CHANNEL_IDS in server .env.
class RssFeedPollerJob < ApplicationJob
  queue_as :background

  FETCH_TIMEOUT          = 15      # seconds per feed
  SEEN_TTL               = 24.hours
  MAX_PER_RUN            = 5       # max new items posted per feed per run
  POST_DELAY             = 1.1     # seconds between Slack posts (rate limit: ~1/sec)
  MAX_ITEM_AGE           = 7.days  # skip items older than this (mark seen, don't post)
  MAX_CONSECUTIVE_ERRORS = 5       # consecutive fetch failures before backing off
  FETCH_BACKOFF_TTL      = 6.hours # how long to skip a feed after hitting the error limit

  def perform
    unless rss_parser_available?
      Rails.logger.warn("[RssFeedPollerJob] RSS parser unavailable — skipping feed poll")
      return
    end

    channel_id = feed_channel_id
    unless channel_id
      Rails.logger.warn("[RssFeedPollerJob] SLACK_FEED_CHANNEL_IDS not set — skipping")
      return
    end

    # Tracks channels that hit a Slack rate limit this run so we stop posting to them.
    ratelimited_channels = Set.new

    feed_urls.each do |url|
      poll(url, channel_id, ratelimited_channels)
    rescue => e
      Rails.logger.warn("[RssFeedPollerJob] Error polling #{url}: #{e.message}")
    end
  end

  private

  def rss_parser_available?
    return true if defined?(RSS::Parser)

    require "rss"
    true
  rescue LoadError => e
    Rails.logger.warn("[RssFeedPollerJob] RSS parser load failed: #{e.message}")
    false
  end

  def feed_channel_id
    ENV.fetch("SLACK_FEED_CHANNEL_IDS", "").split(",").map(&:strip).first.presence
  end

  def feed_urls
    ENV.fetch("RSS_FEED_URLS", "").split(",").map(&:strip).reject(&:empty?)
  end

  def poll(url, channel_id, ratelimited_channels)
    if ratelimited_channels.include?(channel_id)
      Rails.logger.info("[RssFeedPollerJob] #{url} — skipping, channel #{channel_id} is rate-limited this run")
      return
    end

    items = fetch_items(url)
    unseen = items.reject { |item| seen?(item) }

    # Silently mark and skip items that are too old to be useful
    old, fresh = unseen.partition { |item| item_age(item) > MAX_ITEM_AGE }
    old.each { |item| mark_seen(item) }

    to_post = fresh.first(MAX_PER_RUN)
    Rails.logger.info("[RssFeedPollerJob] #{url} — #{items.size} items, #{unseen.size} unseen, #{old.size} aged out, #{to_post.size} posting")

    to_post.each do |item|
      text = format_item(item)
      next if text.blank?
      mark_seen(item)
      Slack::Notifier.call(channel: channel_id, text: text)
      sleep(POST_DELAY)
    rescue Slack::Notifier::ApiError => e
      if e.message.include?("ratelimited")
        Rails.logger.warn("[RssFeedPollerJob] Slack rate-limited on channel #{channel_id} — skipping remaining posts this run")
        ratelimited_channels << channel_id
        break
      end
      Rails.logger.warn("[RssFeedPollerJob] Failed to post item from #{url}: #{e.message}")
      sleep(POST_DELAY)
    rescue => e
      Rails.logger.warn("[RssFeedPollerJob] Failed to post item from #{url}: #{e.message}")
      sleep(POST_DELAY)
    end
  end

  def feed_error_cache_key(url)
    "rss_fetch_errors:#{Digest::SHA1.hexdigest(url)}"
  end

  def fetch_backed_off?(url)
    Rails.cache.exist?("#{feed_error_cache_key(url)}:backoff")
  end

  def record_fetch_success(url)
    Rails.cache.delete(feed_error_cache_key(url))
  end

  def record_fetch_failure(url)
    key = feed_error_cache_key(url)
    count = (Rails.cache.read(key).to_i) + 1
    Rails.cache.write(key, count, expires_in: FETCH_BACKOFF_TTL)
    if count >= MAX_CONSECUTIVE_ERRORS
      Rails.logger.warn("[RssFeedPollerJob] #{url} has failed #{count} times in a row — backing off for #{FETCH_BACKOFF_TTL / 3600}h. Remove it from RSS_FEED_URLS or fix the feed.")
      Rails.cache.write("#{feed_error_cache_key(url)}:backoff", 1, expires_in: FETCH_BACKOFF_TTL)
    end
  end

  def fetch_items(url)
    if fetch_backed_off?(url)
      Rails.logger.info("[RssFeedPollerJob] #{url} is backed off due to repeated failures — skipping")
      return []
    end

    raw = URI.open(url, read_timeout: FETCH_TIMEOUT, open_timeout: FETCH_TIMEOUT).read
    feed = RSS::Parser.parse(raw, false)
    record_fetch_success(url)
    return [] unless feed

    feed.respond_to?(:items) ? feed.items : feed.entries
  rescue => e
    Rails.logger.warn("[RssFeedPollerJob] Fetch failed for #{url}: #{e.message}")
    record_fetch_failure(url)
    []
  end

  def item_age(item)
    pub = nil
    pub ||= item.pubDate   if item.respond_to?(:pubDate)
    pub ||= item.published if item.respond_to?(:published)
    pub ||= item.updated   if item.respond_to?(:updated)
    return 0.seconds unless pub
    time = pub.respond_to?(:to_time) ? pub.to_time : Time.parse(pub.to_s)
    Time.current - time
  rescue
    0.seconds
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
