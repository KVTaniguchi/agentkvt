module HouseManifest
  # Detects whether an inbound email is a utility bill from PECO, PGW, or PWD.
  # Checks from_address, subject, and the first 1 KB of body (covers forwarded-message headers).
  class BillDetector
    UTILITIES = {
      "PECO" => {
        from_patterns:    [/@peco\.com\z/i, /@peco-energy\.com\z/i],
        keyword_patterns: [/\bpeco\b/i]
      },
      "PGW" => {
        from_patterns:    [/@pgworks\.com\z/i, /@pgw\.com\z/i],
        keyword_patterns: [/\bpgw\b/i, /philadelphia\s+gas\s+works/i]
      },
      "PWD" => {
        from_patterns:    [/@phila\.gov\z/i],
        keyword_patterns: [/\bpwd\b/i, /philadelphia\s+water\s+dep/i]
      }
    }.freeze

    Result = Data.define(:detected, :utility)

    def self.call(inbound_email)
      new(inbound_email).call
    end

    def initialize(inbound_email)
      @email = inbound_email
    end

    def call
      UTILITIES.each do |utility, patterns|
        if from_match?(patterns[:from_patterns]) || keyword_match?(patterns[:keyword_patterns])
          return Result.new(detected: true, utility: utility)
        end
      end
      Result.new(detected: false, utility: nil)
    end

    private

    def from_match?(patterns)
      return false if @email.from_address.blank?
      patterns.any? { |p| @email.from_address.match?(p) }
    end

    def keyword_match?(patterns)
      text = [ @email.subject.to_s, @email.body_text.to_s.slice(0, 1024) ].join(" ")
      patterns.any? { |p| text.match?(p) }
    end
  end
end
