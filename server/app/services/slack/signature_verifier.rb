module Slack
  class SignatureVerifier
    class Error < StandardError; end
    class InvalidSignatureError < Error; end
    class StaleRequestError < Error; end
    class MissingSigningSecretError < Error; end

    MAX_AGE_SECONDS = 300

    def self.verify!(signing_secret:, request_body:, timestamp_header:, signature_header:)
      raise MissingSigningSecretError if signing_secret.blank?
      raise StaleRequestError if timestamp_header.blank? || signature_header.blank?

      ts = begin
        Integer(timestamp_header, 10)
      rescue ArgumentError, TypeError
        raise StaleRequestError
      end
      raise StaleRequestError if (Time.now.to_i - ts).abs > MAX_AGE_SECONDS

      sig_basestring = "v0:#{timestamp_header}:#{request_body}"
      expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)}"
      raise InvalidSignatureError unless ActiveSupport::SecurityUtils.secure_compare(expected, signature_header)
    end
  end
end
