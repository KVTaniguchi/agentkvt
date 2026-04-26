require "test_helper"
require "securerandom"

module HouseManifest
  class BillExtractorTest < ActiveSupport::TestCase
    setup do
      @workspace = Workspace.create!(name: "Extractor Test", slug: "extractor-#{SecureRandom.hex(4)}")
      @email = @workspace.inbound_emails.create!(
        message_id:   "msg-peco-1",
        from_address: "billing@peco.com",
        subject:      "Your April PECO Bill",
        body_text:    "Amount Due: $134.56. Due Date: April 20, 2026. Billing period: March 1 – March 31, 2026. Account: 1234-5678."
      )
    end

    test "returns extracted fields from LLM response" do
      llm_response = {
        "amount_due"           => 134.56,
        "due_date"             => "2026-04-20",
        "billing_period_start" => "2026-03-01",
        "billing_period_end"   => "2026-03-31",
        "account_number"       => "1234-5678"
      }.to_json

      fake_client = Object.new
      fake_client.define_singleton_method(:chat) { |**| llm_response }

      result = OllamaClient.stub(:new, fake_client) do
        BillExtractor.call(@email, utility: "PECO")
      end

      assert_equal 134.56, result["amount_due"]
      assert_equal "2026-04-20", result["due_date"]
      assert_equal "2026-03-01", result["billing_period_start"]
      assert_equal "2026-03-31", result["billing_period_end"]
      assert_equal "1234-5678", result["account_number"]
    end

    test "omits null fields from result" do
      llm_response = {
        "amount_due"           => 134.56,
        "due_date"             => nil,
        "billing_period_start" => nil,
        "billing_period_end"   => nil,
        "account_number"       => nil
      }.to_json

      fake_client = Object.new
      fake_client.define_singleton_method(:chat) { |**| llm_response }

      result = OllamaClient.stub(:new, fake_client) do
        BillExtractor.call(@email, utility: "PECO")
      end

      assert_equal 134.56, result["amount_due"]
      refute result.key?("due_date")
      refute result.key?("account_number")
    end

    test "returns empty hash when LLM errors" do
      fake_client = Object.new
      fake_client.define_singleton_method(:chat) { |**| raise "connection refused" }

      result = OllamaClient.stub(:new, fake_client) do
        BillExtractor.call(@email, utility: "PECO")
      end

      assert_equal({}, result)
    end

    test "returns empty hash on malformed JSON" do
      fake_client = Object.new
      fake_client.define_singleton_method(:chat) { |**| "not json at all" }

      result = OllamaClient.stub(:new, fake_client) do
        BillExtractor.call(@email, utility: "PECO")
      end

      assert_equal({}, result)
    end

    test "coerces amount_due string to float" do
      llm_response = { "amount_due" => "134.56" }.to_json

      fake_client = Object.new
      fake_client.define_singleton_method(:chat) { |**| llm_response }

      result = OllamaClient.stub(:new, fake_client) do
        BillExtractor.call(@email, utility: "PECO")
      end

      assert_equal 134.56, result["amount_due"]
    end
  end
end
