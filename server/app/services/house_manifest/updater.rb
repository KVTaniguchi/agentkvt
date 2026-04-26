module HouseManifest
  # Atomically merges new bill fields into house_manifest.json.
  # Uses an exclusive file lock so concurrent Solid Queue workers don't corrupt the file.
  class Updater
    MANIFEST_PATH = Pathname.new(
      ENV.fetch("HOUSE_MANIFEST_PATH", File.join(Dir.home, ".agentkvt", "house_manifest.json"))
    ).freeze

    SCHEMA_VERSION = 1

    def self.call(utility:, fields:, source_message_id: nil)
      new(utility: utility, fields: fields, source_message_id: source_message_id).call
    end

    def initialize(utility:, fields:, source_message_id: nil)
      @utility           = utility
      @fields            = fields
      @source_message_id = source_message_id
    end

    def call
      return if @fields.empty?

      MANIFEST_PATH.dirname.mkpath

      File.open(MANIFEST_PATH, File::RDWR | File::CREAT, 0o644) do |f|
        f.flock(File::LOCK_EX)
        manifest = parse_manifest(f.read)
        manifest = merge(manifest)
        f.rewind
        f.truncate(0)
        f.write(JSON.pretty_generate(manifest))
        f.flush
      end

      Rails.logger.info("[HouseManifest::Updater] Updated #{@utility} → #{MANIFEST_PATH}")
    rescue => e
      Rails.logger.error("[HouseManifest::Updater] Failed to update manifest: #{e.message}")
    end

    private

    def parse_manifest(content)
      return empty_manifest if content.blank?
      JSON.parse(content)
    rescue JSON::ParseError
      empty_manifest
    end

    def merge(manifest)
      manifest["last_updated_at"] = Time.current.iso8601
      manifest["utilities"]     ||= {}
      manifest["utilities"][@utility] = {
        "last_updated_at"   => Time.current.iso8601,
        "source_message_id" => @source_message_id
      }.merge(@fields).compact
      manifest
    end

    def empty_manifest
      { "schema_version" => SCHEMA_VERSION, "last_updated_at" => nil, "utilities" => {} }
    end
  end
end
