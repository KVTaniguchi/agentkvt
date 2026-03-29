module V1
  class ObjectivesController < BaseController
    def index
      objectives = current_workspace.objectives.recent_first
      render json: { objectives: objectives.map { |o| serialize_objective(o) } }
    end

    def create
      objective = current_workspace.objectives.create!(objective_params)

      # Kick off LLM task decomposition for active objectives immediately
      kickoff_objective(objective) if objective.status == "active"

      render json: { objective: serialize_objective(objective) }, status: :created
    end

    def show
      objective = current_workspace.objectives.find(params[:id])
      # Match Mac/client UUID casing (uppercase) vs DB lowercase by normalizing both sides.
      agent_logs = current_workspace.agent_logs
        .where("LOWER(metadata_json ->> 'objective_id') = LOWER(?)", objective.id.to_s)
        .recent_first
        .limit(30)

      render json: {
        objective: serialize_objective(objective),
        tasks: objective.tasks.pending_first.map { |t| serialize_task(t) },
        research_snapshots: objective.research_snapshots.recent_first.map { |s| serialize_research_snapshot(s) },
        agent_logs: agent_logs.map { |log| serialize_agent_log(log) }
      }
    end

    def update
      objective = current_workspace.objectives.find(params[:id])
      objective.update!(objective_params)

      # Activating an objective should either create fresh tasks or re-enqueue pending ones.
      if objective.saved_change_to_status? && objective.status == "active"
        kickoff_objective(objective)
      end

      render json: { objective: serialize_objective(objective) }
    end

    def run_now
      objective = current_workspace.objectives.find(params[:id])
      kickoff_objective(objective)

      render json: { objective: serialize_objective(objective.reload) }
    end

    # Moves in_progress tasks back to pending (clears summaries) then re-dispatches — for stuck Mac/webhook runs.
    def reset_stuck_tasks_and_run
      objective = current_workspace.objectives.find(params[:id])
      objective.tasks.where(status: "in_progress").find_each do |task|
        task.update!(status: "pending", result_summary: nil)
      end
      kickoff_objective(objective)

      render json: { objective: serialize_objective(objective.reload) }
    end

    # Resets every task to pending, clears all research snapshots, and re-dispatches
    # so the user can redo research from scratch from the iOS app.
    def rerun
      objective = current_workspace.objectives.find(params[:id])
      objective.tasks.find_each do |task|
        task.update!(status: "pending", result_summary: nil)
      end
      objective.research_snapshots.destroy_all
      kickoff_objective(objective)

      render json: { objective: serialize_objective(objective.reload) }
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

    def kickoff_objective(objective)
      objective.update!(status: "active") unless objective.status == "active"

      if objective.tasks.empty?
        ObjectivePlanner.new.call(objective)
        return
      end

      objective.tasks.where(status: "failed").find_each do |task|
        task.update!(status: "pending", result_summary: nil)
      end

      objective.tasks.where(status: "pending").find_each do |task|
        TaskExecutorJob.perform_later(task.id.to_s)
      end
    end
  end
end
