require "test_helper"
require "securerandom"

module Slack
  class MessageClassifierTest < ActiveSupport::TestCase
    setup do
      @workspace = Workspace.create!(name: "Slack Classifier Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    end

    test "feed bot messages without a relevant objective skip the llm" do
      objective = @workspace.objectives.create!(goal: "Compare Capital One lounge access options", status: "active")
      message = SlackMessage.create!(
        workspace: @workspace,
        slack_team_id: "T1",
        channel_id: "C1",
        message_ts: "1.0",
        slack_user_id: "B1",
        text: "SEPTA says the Broad Street Line will use a reduced schedule tonight",
        intake_kind: "feed_bot",
        trust_tier: "medium"
      )

      fake_client = Object.new
      fake_client.define_singleton_method(:chat) { |**| flunk "classifier should not call Ollama for unrelated feed bot messages" }

      result = OllamaClient.stub(:new, fake_client) do
        MessageClassifier.call(message, objectives: [objective])
      end

      assert_equal "ignore", result["action"]
      assert_nil result["objective_id"]
    end

    test "classifier only sends shortlisted relevant objectives to the llm" do
      relevant = @workspace.objectives.create!(goal: "Track SEPTA and South Philly transit alerts", status: "active")
      unrelated = @workspace.objectives.create!(goal: "Compare Amex and Chase premium card lounge perks", status: "active")
      message = SlackMessage.create!(
        workspace: @workspace,
        slack_team_id: "T1",
        channel_id: "C1",
        message_ts: "2.0",
        slack_user_id: "U1",
        text: "SEPTA posted a detour for South Philly bus service tonight",
        intake_kind: "user_typed",
        trust_tier: "low"
      )

      captured_messages = nil
      fake_client = Object.new
      fake_client.define_singleton_method(:chat) do |**kwargs|
        captured_messages = kwargs[:messages]
        { "action" => "ignore", "summary" => "", "objective_id" => nil }.to_json
      end

      OllamaClient.stub(:new, fake_client) do
        MessageClassifier.call(message, objectives: [unrelated, relevant])
      end

      system_prompt = captured_messages.first[:content]
      assert_includes system_prompt, relevant.id.to_s
      assert_includes system_prompt, relevant.goal
      refute_includes system_prompt, unrelated.id.to_s
      refute_includes system_prompt, unrelated.goal
    end
  end
end
