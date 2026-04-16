class HealthScoutJob < ApplicationJob
  queue_as :background

  def perform
    # Note: Depending on workspace configuration, this might need to target a specific
    # workspace dynamically. For now, we take the first available.
    workspace = Workspace.first
    return unless workspace

    objective = workspace.objectives.find_or_create_by!(
      goal: "Monitor Allergist Schedule",
      status: "active",
      creation_source: "manual"
    )

    # Instead of direct headless browser scrape, push the intent as a new Task.
    # The Mac Runner processes this pending Task.
    instructions = <<~INSTRUCTIONS
      Load the allergist website using your `headless_browser_scout` tool.
      Extract the open hours for this current week.
      Use your snapshot tool to write the findings back to Postgres.
      The state key must be `allergist_status`.
    INSTRUCTIONS

    objective.tasks.create!(
      description: instructions,
      status: "pending"
    )
  end
end
