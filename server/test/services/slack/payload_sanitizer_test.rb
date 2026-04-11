require "test_helper"

class SlackPayloadSanitizerTest < ActiveSupport::TestCase
  test "redacts token-like keys in nested hashes" do
    input = {
      "type" => "message",
      "token" => "xoxb-secret",
      "nested" => { "api_key" => "shh" }
    }
    out = Slack::PayloadSanitizer.sanitize(input)
    assert_equal "[REDACTED]", out["token"]
    assert_equal "[REDACTED]", out["nested"]["api_key"]
    assert_equal "message", out["type"]
  end
end
