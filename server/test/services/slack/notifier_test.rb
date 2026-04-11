require "test_helper"

class Slack::NotifierTest < ActiveSupport::TestCase
  test "raises TokenMissingError when no token is available" do
    with_env("SLACK_BOT_TOKEN" => nil) do
      assert_raises(Slack::Notifier::TokenMissingError) do
        Slack::Notifier.call(channel: "C0TEST", text: "hi")
      end
    end
  end

  test "raises ApiError when Slack returns ok=false" do
    with_fake_http({ "ok" => false, "error" => "channel_not_found" }) do
      with_env("SLACK_BOT_TOKEN" => "xoxb-test") do
        assert_raises(Slack::Notifier::ApiError) do
          Slack::Notifier.call(channel: "C0TEST", text: "hi")
        end
      end
    end
  end

  test "returns parsed body on success" do
    with_fake_http({ "ok" => true, "ts" => "12345.6789" }) do
      with_env("SLACK_BOT_TOKEN" => "xoxb-test") do
        result = Slack::Notifier.call(channel: "C0TEST", text: "hi")
        assert result["ok"]
        assert_equal "12345.6789", result["ts"]
      end
    end
  end

  private

  FakeResponse = Struct.new(:body)

  def with_fake_http(response_body)
    fake_response = FakeResponse.new(response_body.to_json)
    Net::HTTP.stub(:new, ->(_host, _port) {
      Object.new.tap { |o|
        o.define_singleton_method(:use_ssl=) { |_| }
        o.define_singleton_method(:request) { |_| fake_response }
      }
    }) { yield }
  end

  def with_env(overrides)
    saved = overrides.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
  end
end
