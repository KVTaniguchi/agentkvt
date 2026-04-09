module V1
  class ObjectivesController < BaseController
    def index
      objectives = current_workspace.objectives.recent_first
      render json: { objectives: objectives.map { |o| serialize_objective(o) } }
    end

    def create
      objective = current_workspace.objectives.create!(objective_params)

      # Kick off LLM task decomposition for active objectives immediately
      ObjectiveKickoff.new.call(objective) if objective.status == "active"

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
        agent_logs: agent_logs.map { |log| serialize_agent_log(log) },
        online_agent_registrations_count: current_workspace.agent_registrations.online.count
      }
    end

    def update
      objective = current_workspace.objectives.find(params[:id])
      objective.update!(objective_params)

      # Activating an objective should either create fresh tasks or re-enqueue pending ones.
      if objective.saved_change_to_status? && objective.status == "active"
        ObjectiveKickoff.new.call(objective)
      end

      render json: { objective: serialize_objective(objective) }
    end

    def run_now
      objective = current_workspace.objectives.find(params[:id])
      ObjectiveKickoff.new.call(objective)

      render json: { objective: serialize_objective(objective.reload) }
    end

    # Moves in_progress tasks back to pending (clears summaries) then re-dispatches — for stuck Mac/webhook runs.
    def reset_stuck_tasks_and_run
      objective = current_workspace.objectives.find(params[:id])
      objective.tasks.where(status: "in_progress").find_each do |task|
        task.update!(status: "pending", result_summary: nil, claimed_at: nil, claimed_by_agent_id: nil)
      end
      ObjectiveKickoff.new.call(objective)

      render json: { objective: serialize_objective(objective.reload) }
    end

    # Resets every task to pending, clears all research snapshots, and re-dispatches
    # so the user can redo research from scratch from the iOS app.
    def rerun
      objective = current_workspace.objectives.find(params[:id])
      objective.tasks.find_each do |task|
        task.update!(status: "pending", result_summary: nil, claimed_at: nil, claimed_by_agent_id: nil)
      end
      objective.research_snapshots.destroy_all
      ObjectiveKickoff.new.call(objective)

      render json: { objective: serialize_objective(objective.reload) }
    end

    def destroy
      objective = current_workspace.objectives.find(params[:id])
      objective.destroy!

      head :no_content
    end

    def presentation
      objective = current_workspace.objectives.find(params[:id])

      if objective.presentation_json.present? && !presentation_stale?(objective)
        cached = JSON.parse(objective.presentation_json)
        return render json: { layout: cached["layout"], status: "ready" }
      end

      # Debounce: only enqueue a new job if one hasn't been enqueued in the last 90 seconds.
      # Without this guard, iOS polling every ~5s spawns a new inference job on every request
      # while the previous job is still running, creating a compounding storm on Ollama.
      unless objective.presentation_enqueued_at&.> 90.seconds.ago
        objective.update_column(:presentation_enqueued_at, Time.current)
        ObjectivePresentationJob.perform_later(objective.id.to_s)
      end

      render json: { layout: nil, status: "generating" }, status: :accepted
    end

    private

    def presentation_stale?(objective)
      return true unless objective.presentation_generated_at

      latest_snapshot_at = objective.research_snapshots.maximum(:updated_at)
      return false if latest_snapshot_at.nil?

      latest_snapshot_at > objective.presentation_generated_at
    end

    def objective_params
      params.require(:objective).permit(
        :goal,
        :status,
        :priority,
        :objective_kind,
        :creation_source,
        brief_json: [
          :deliverable,
          { context: [], success_criteria: [], constraints: [], preferences: [], open_questions: [] }
        ]
      )
    end
  end
end
