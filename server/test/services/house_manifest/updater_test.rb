require "test_helper"
require "tmpdir"

module HouseManifest
  class UpdaterTest < ActiveSupport::TestCase
    setup do
      @tmpdir  = Dir.mktmpdir
      @tmppath = File.join(@tmpdir, "house_manifest.json")
    end

    teardown do
      FileUtils.remove_entry(@tmpdir)
    end

    def call(utility: "PECO", fields: {}, source_message_id: nil)
      stub_const(Updater, :MANIFEST_PATH, Pathname.new(@tmppath)) do
        Updater.call(utility: utility, fields: fields, source_message_id: source_message_id)
      end
    end

    def read_manifest
      JSON.parse(File.read(@tmppath))
    end

    test "creates manifest file with utility entry" do
      call(
        utility:           "PECO",
        fields:            { "amount_due" => 134.56, "due_date" => "2026-04-20" },
        source_message_id: "msg-1"
      )

      manifest = read_manifest
      assert_equal 1, manifest["schema_version"]
      assert manifest["last_updated_at"]
      peco = manifest["utilities"]["PECO"]
      assert_equal 134.56, peco["amount_due"]
      assert_equal "2026-04-20", peco["due_date"]
      assert_equal "msg-1", peco["source_message_id"]
    end

    test "merges new data over existing entry" do
      call(utility: "PECO", fields: { "amount_due" => 100.0, "account_number" => "1234" })
      call(utility: "PECO", fields: { "amount_due" => 134.56, "due_date" => "2026-04-20" })

      peco = read_manifest["utilities"]["PECO"]
      assert_equal 134.56, peco["amount_due"]
      assert_equal "2026-04-20", peco["due_date"]
    end

    test "preserves other utilities when updating one" do
      call(utility: "PGW", fields: { "amount_due" => 55.0 })
      call(utility: "PECO", fields: { "amount_due" => 134.56 })

      manifest = read_manifest
      assert manifest["utilities"]["PGW"]
      assert manifest["utilities"]["PECO"]
    end

    test "skips write when fields are empty" do
      call(utility: "PECO", fields: {})
      refute File.exist?(@tmppath)
    end

    test "repairs corrupted manifest without raising" do
      File.write(@tmppath, "not valid json {{{")
      assert_nothing_raised do
        call(utility: "PECO", fields: { "amount_due" => 134.56 })
      end
      assert_equal 134.56, read_manifest["utilities"]["PECO"]["amount_due"]
    end

    private

    def stub_const(klass, const_name, value)
      old = klass.const_get(const_name)
      klass.send(:remove_const, const_name)
      klass.const_set(const_name, value)
      yield
    ensure
      klass.send(:remove_const, const_name)
      klass.const_set(const_name, old)
    end
  end
end
