class SlackMessageProcessorJob < ApplicationJob
  queue_as :inference

  def perform(slack_message_id)
    message = SlackMessage.find_by(id: slack_message_id)
    return unless message

    workspace  = message.workspace
    objectives = workspace.objectives.where(status: %w[pending active]).order(created_at: :desc).limit(20)
    result     = Slack::MessageClassifier.call(message, objectives: objectives)

    return unless result["action"] == "append_research"

    objective = workspace.objectives.find_by(id: result["objective_id"])
    return unless objective

    ResearchSnapshot.create!(
      objective:  objective,
      key:        "slack_signal",
      value:      result["summary"].presence || message.text.truncate(500),
      checked_at: Time.current
    )
  end
end
