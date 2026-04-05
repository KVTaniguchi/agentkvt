class ObjectivePlannerJob < ApplicationJob
  queue_as :inference

  # Decomposes an objective into tasks via Ollama and enqueues TaskExecutorJob for each.
  # Running on the :inference queue keeps slow LLM calls off Puma threads and avoids
  # holding ActiveRecord connections open during inference.
  def perform(objective_id)
    objective = Objective.find_by(id: objective_id)
    return unless objective

    ObjectivePlanner.new.call(objective)
  end
end
