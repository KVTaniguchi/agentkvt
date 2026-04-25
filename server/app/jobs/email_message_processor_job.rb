class EmailMessageProcessorJob < ApplicationJob
  queue_as :default

  def perform(inbound_email_id)
    email = InboundEmail.find_by(id: inbound_email_id)
    return unless email

    workspace  = email.workspace
    objectives = workspace.objectives.where(status: %w[pending active]).order(created_at: :desc).limit(20)
    result     = Email::MessageClassifier.call(email, objectives: objectives)

    return unless result["action"] == "append_research"

    objective = workspace.objectives.find_by(id: result["objective_id"])
    return unless objective

    ResearchSnapshot.upsert_for_objective!(
      objective:  objective,
      key:        "email_signal",
      value:      result["summary"].presence || [ email.subject, email.body_text ].compact.join(" — ").truncate(500),
      checked_at: Time.current
    )
  end
end
