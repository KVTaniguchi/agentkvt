module V1
  class ObjectivesController < BaseController
    def index
      objectives = current_workspace.objectives.recent_first
      render json: { objectives: objectives.map { |o| serialize_objective(o) } }
    end

    def create
      objective = current_workspace.objectives.create!(objective_params)

      # Kick off LLM task decomposition for active objectives immediately
      ObjectivePlanner.new.call(objective) if objective.status == "active"

      render json: { objective: serialize_objective(objective) }, status: :created
    end

    def show
      objective = current_workspace.objectives.find(params[:id])

      render json: {
        objective: serialize_objective(objective),
        tasks: objective.tasks.pending_first.map { |t| serialize_task(t) },
        research_snapshots: objective.research_snapshots.recent_first.map { |s| serialize_research_snapshot(s) }
      }
    end

    def update
      objective = current_workspace.objectives.find(params[:id])
      objective.update!(objective_params)

      # Activating an objective that never got tasks (e.g. was pending, or LLM failed earlier).
      if objective.saved_change_to_status? && objective.status == "active" && objective.tasks.empty?
        ObjectivePlanner.new.call(objective)
      end

      render json: { objective: serialize_objective(objective) }
    end

    def destroy
      objective = current_workspace.objectives.find(params[:id])
      objective.destroy!

      head :no_content
    end

    private

    def objective_params
      params.require(:objective).permit(:goal, :status, :priority)
    end
  end
end
