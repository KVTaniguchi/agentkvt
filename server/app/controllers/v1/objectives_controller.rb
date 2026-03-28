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

    private

    def objective_params
      params.require(:objective).permit(:goal, :status, :priority)
    end
  end
end
