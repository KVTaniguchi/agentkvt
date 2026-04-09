module V1
  class ObjectiveDraftMessagesController < BaseController
    def create
      draft = find_draft!
      if draft.status == "finalized"
        return render json: { error: "Draft has already been finalized" }, status: :unprocessable_entity
      end

      draft.objective_draft_messages.create!(
        role: "user",
        content: message_params.fetch(:content)
      )

      turn = ObjectiveComposer.new.call(draft)

      draft.transaction do
        draft.objective_draft_messages.create!(
          role: "assistant",
          content: turn.fetch("assistant_message")
        )
        draft.update!(
          brief_json: turn.fetch("brief_json"),
          suggested_goal: turn.fetch("suggested_goal"),
          assistant_message: turn.fetch("assistant_message"),
          missing_fields: turn.fetch("missing_fields"),
          ready_to_finalize: turn.fetch("ready_to_finalize")
        )
      end

      render json: { objective_draft: serialize_objective_draft(draft.reload) }, status: :created
    end

    private

    def find_draft!
      current_workspace.objective_drafts.stale_unfinalized.find_each(&:destroy)
      current_workspace.objective_drafts.find(params[:objective_draft_id])
    end

    def message_params
      params.require(:objective_draft_message).permit(:content)
    end
  end
end
