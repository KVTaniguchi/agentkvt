module Slack
  # Removes obvious secret-bearing keys before persisting Slack JSON for audit/debug.
  module PayloadSanitizer
    SENSITIVE_KEY = /token|secret|password|authorization|api_key/i

    module_function

    def sanitize(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), out|
          if k.to_s.match?(SENSITIVE_KEY)
            out[k] = "[REDACTED]"
          else
            out[k] = sanitize(v)
          end
        end
      when Array
        value.map { |x| sanitize(x) }
      else
        value
      end
    end
  end
end
