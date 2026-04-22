Rails.application.routes.draw do
  get "/healthz", to: "health#show"

  namespace :v1 do
    post "slack/events", to: "slack/events#create"

    post :chat_wake, to: "chat_wakes#create"

    resource :bootstrap, only: :show
    resources :family_members, only: [:index, :create]
    resources :chat_threads, only: [:index, :create, :show] do
      resources :chat_messages, only: [:create]
    end
    resources :objective_drafts, only: [:create, :show] do
      post :finalize, on: :member
      resources :messages, only: [:create], controller: "objective_draft_messages"
    end
    resources :inbound_files, only: [:index, :create]
    resources :client_telemetry_snapshots, only: [:create]

    resources :life_context, only: [:index, :update], controller: "life_context_entries", param: :key
    resources :agent_logs, only: [:index] do
      get :digest, on: :collection
    end
    resources :objectives, only: [:index, :create, :show, :update, :destroy] do
      post :feedback, on: :member
      post :approve_plan, on: :member
      post :regenerate_plan, on: :member
      post :run_now, on: :member
      post :reset_stuck_tasks_and_run, on: :member
      post :rerun, on: :member
      get :presentation, on: :member
      resources :research_snapshots, only: [] do
        resources :feedback, only: [:create, :update], controller: "research_snapshot_feedbacks"
      end
      resources :objective_feedbacks, only: [:update] do
        post :approve_plan, on: :member
        post :regenerate_plan, on: :member
      end
    end

    namespace :agent do

      get :chat_wake, to: "chat_wakes#show"
      post :logs, to: "agent_logs#create"
      post :register, to: "registrations#upsert"
      post "chat_messages/claim_next", to: "chat_messages#claim_next"
      post "chat_messages/:id/complete", to: "chat_messages#complete"
      post "chat_messages/:id/fail", to: "chat_messages#fail"
      resources :inbound_files, only: [:index] do
        post :mark_processed, on: :member
      end



      resources :objectives, only: [] do
        resources :research_snapshots, only: [:index, :create]
        resources :tasks, only: [] do
          post :fail, on: :member
          post :release, on: :member
        end
      end
    end
  end
end
