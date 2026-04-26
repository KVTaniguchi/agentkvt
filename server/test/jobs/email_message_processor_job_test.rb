require "test_helper"
require "securerandom"

class EmailMessageProcessorJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Email Job Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective = @workspace.objectives.create!(goal: "Track AI research signals", status: "active")
    @email = @workspace.inbound_emails.create!(
      message_id: "msg-abc",
      subject: "New AI paper published",
      body_text: "Researchers at DeepMind released a new multi-agent coordination paper."
    )
  end

  test "append_research upserts the email_signal snapshot" do
    @objective.research_snapshots.create!(
      key: "email_signal",
      value: "Earlier signal",
      checked_at: 1.hour.ago
    )

    classifier_result = {
      "action" => "append_research",
      "objective_id" => @objective.id,
      "summary" => "DeepMind released a multi-agent coordination paper"
    }

    Email::MessageClassifier.stub(:call, classifier_result) do
      assert_no_difference -> { @objective.research_snapshots.count } do
        EmailMessageProcessorJob.new.perform(@email.id)
      end
    end

    snapshot = @objective.research_snapshots.find_by!(key: "email_signal")
    assert_equal "DeepMind released a multi-agent coordination paper", snapshot.value
  end

  test "ignore result skips snapshot creation" do
    Email::MessageClassifier.stub(:call, { "action" => "ignore", "summary" => "", "objective_id" => nil }) do
      assert_no_difference -> { ResearchSnapshot.count } do
        EmailMessageProcessorJob.new.perform(@email.id)
      end
    end
  end

  test "calls manifest pipeline for utility bill emails" do
    bill_email = @workspace.inbound_emails.create!(
      message_id:   "msg-peco",
      from_address: "billing@peco.com",
      subject:      "Your PECO Bill",
      body_text:    "Amount due: $134.56"
    )

    updater_calls = []
    fake_updater = ->(utility:, fields:, source_message_id:) { updater_calls << { utility: utility, fields: fields } }

    Email::MessageClassifier.stub(:call, { "action" => "ignore", "summary" => "", "objective_id" => nil }) do
      HouseManifest::BillExtractor.stub(:call, { "amount_due" => 134.56 }) do
        HouseManifest::Updater.stub(:call, fake_updater) do
          EmailMessageProcessorJob.new.perform(bill_email.id)
        end
      end
    end

    assert_equal 1, updater_calls.size
    assert_equal "PECO", updater_calls.first[:utility]
  end

  test "skips manifest pipeline for non-utility emails" do
    updater_calls = []
    fake_updater = ->(utility:, fields:, source_message_id:) { updater_calls << utility }

    Email::MessageClassifier.stub(:call, { "action" => "ignore", "summary" => "", "objective_id" => nil }) do
      HouseManifest::Updater.stub(:call, fake_updater) do
        EmailMessageProcessorJob.new.perform(@email.id)
      end
    end

    assert_empty updater_calls
  end
end
