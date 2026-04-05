class ObjectivePresentationJob < ApplicationJob
  queue_as :inference

  # Generates the iOS SwiftUI layout JSON for an objective via Ollama and persists it.
  # Runs on the :inference queue so slow LLM generation does not tie up Puma threads.
  def perform(objective_id)
    objective = Objective.find_by(id: objective_id)
    return unless objective

    result = ObjectivePresentationBuilder.new.call(objective)
    return unless result

    objective.update_columns(
      presentation_json: result,
      presentation_generated_at: Time.current
    )
  end
end
