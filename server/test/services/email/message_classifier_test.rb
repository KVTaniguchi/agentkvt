require "test_helper"
require "securerandom"

module Email
  class MessageClassifierTest < ActiveSupport::TestCase
    setup do
      @workspace = Workspace.create!(name: "Email Classifier Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    end

    test "returns ignore when no objectives score positively" do
      @workspace.objectives.create!(goal: "Compare Amex and Chase premium card lounge perks", status: "active")
      email = @workspace.inbound_emails.create!(
        message_id: "msg-1",
        subject: "Your order has shipped",
        body_text: "Your package is on its way."
      )

      fake_client = Object.new
      fake_client.define_singleton_method(:chat) { |**| flunk "classifier should not call Ollama when no objectives match" }

      result = OllamaClient.stub(:new, fake_client) do
        MessageClassifier.call(email, objectives: @workspace.objectives.to_a)
      end

      assert_equal "ignore", result["action"]
      assert_nil result["objective_id"]
    end

    test "only sends shortlisted relevant objectives to the llm" do
      relevant   = @workspace.objectives.create!(goal: "Track SEPTA and South Philly transit alerts", status: "active")
      unrelated  = @workspace.objectives.create!(goal: "Compare Amex and Chase premium card lounge perks", status: "active")
      email = @workspace.inbound_emails.create!(
        message_id: "msg-2",
        subject: "SEPTA service alert",
        body_text: "SEPTA posted a detour for South Philly bus service tonight."
      )

      captured_messages = nil
      fake_client = Object.new
      fake_client.define_singleton_method(:chat) do |**kwargs|
        captured_messages = kwargs[:messages]
        { "action" => "ignore", "summary" => "", "objective_id" => nil }.to_json
      end

      OllamaClient.stub(:new, fake_client) do
        MessageClassifier.call(email, objectives: [unrelated, relevant])
      end

      system_prompt = captured_messages.first[:content]
      assert_includes system_prompt, relevant.id.to_s
      assert_includes system_prompt, relevant.goal
      refute_includes system_prompt, unrelated.id.to_s
      refute_includes system_prompt, unrelated.goal
    end
  end
end
