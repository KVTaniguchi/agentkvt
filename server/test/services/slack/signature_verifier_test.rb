require "test_helper"
require "openssl"

class SlackSignatureVerifierTest < ActiveSupport::TestCase
  SECRET = "signing_secret_test"

  test "verify! accepts a valid v0 signature" do
    body = '{"hello":"world"}'
    ts = Time.now.to_i.to_s
    expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, "v0:#{ts}:#{body}")}"

    assert_nothing_raised do
      Slack::SignatureVerifier.verify!(
        signing_secret: SECRET,
        request_body: body,
        timestamp_header: ts,
        signature_header: expected
      )
    end
  end

  test "verify! raises InvalidSignatureError when signature wrong" do
    body = "{}"
    ts = Time.now.to_i.to_s

    assert_raises(Slack::SignatureVerifier::InvalidSignatureError) do
      Slack::SignatureVerifier.verify!(
        signing_secret: SECRET,
        request_body: body,
        timestamp_header: ts,
        signature_header: "v0=deadbeef"
      )
    end
  end

  test "verify! raises StaleRequestError when timestamp too old" do
    body = "{}"
    ts = (Time.now.to_i - 400).to_s
    expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, "v0:#{ts}:#{body}")}"

    assert_raises(Slack::SignatureVerifier::StaleRequestError) do
      Slack::SignatureVerifier.verify!(
        signing_secret: SECRET,
        request_body: body,
        timestamp_header: ts,
        signature_header: expected
      )
    end
  end

  test "verify! raises MissingSigningSecretError when secret blank" do
    assert_raises(Slack::SignatureVerifier::MissingSigningSecretError) do
      Slack::SignatureVerifier.verify!(
        signing_secret: "",
        request_body: "{}",
        timestamp_header: Time.now.to_i.to_s,
        signature_header: "v0=abc"
      )
    end
  end
end
