class SlackMessageProcessorJob < ApplicationJob
  queue_as :inference

  def perform(slack_message_id)
    message = SlackMessage.find_by(id: slack_message_id)
    return unless message

    workspace  = message.workspace
    objectives = workspace.objectives.where(status: %w[pending active]).order(created_at: :desc).limit(20)
    result     = Slack::MessageClassifier.call(message, objectives: objectives)

    case result["action"]
    when "notify_user"
      notify(workspace, result)
    when "append_research"
      append_research(workspace, message, result)
    when "create_objective"
      create_objective(workspace, message, result)
    # "ignore" — do nothing
    end
  end

  private

  def owner_user_id
    ENV["SLACK_OWNER_USER_ID"].presence
  end

  def notify(workspace, result)
    return unless owner_user_id

    urgency_tag = result["urgency"] == "high" ? " :rotating_light:" : ""
    Slack::Notifier.call(channel: owner_user_id, text: "#{result['summary']}#{urgency_tag}", workspace: workspace)
  end

  def append_research(workspace, message, result)
    objective = workspace.objectives.find_by(id: result["objective_id"])
    unless objective
      notify(workspace, result.merge("summary" => "[Research signal, no matching objective] #{result['summary']}"))
      return
    end

    ResearchSnapshot.create!(
      objective:  objective,
      key:        "slack_signal",
      value:      result["summary"].presence || message.text.truncate(500),
      checked_at: Time.current
    )
  end

  def create_objective(workspace, message, result)
    summary   = result["summary"].presence || message.text.truncate(200)
    objective = Objective.create!(
      workspace:       workspace,
      goal:            summary,
      status:          "pending",
      creation_source: "manual",
      brief_json:      { "slack_signal" => message.text }
    )
    notify(workspace, result.merge("summary" => "New objective created from Slack signal: #{objective.goal}"))
  end
end
