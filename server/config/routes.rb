Rails.application.routes.draw do
  get "/healthz", to: "health#show"

  namespace :v1 do
    post :chat_wake, to: "chat_wakes#create"

    resource :bootstrap, only: :show
    resources :family_members, only: [:index, :create]

    resources :life_context, only: [:index, :update], controller: "life_context_entries", param: :key
    resources :action_items, only: [:index] do
      post :handle, on: :member
    end
    resources :agent_logs, only: [:index]
    resources :objectives, only: [:index, :create, :show, :update, :destroy] do
      post :run_now, on: :member
      post :reset_stuck_tasks_and_run, on: :member
      post :rerun, on: :member
      get :presentation, on: :member
    end

    namespace :agent do

      get :chat_wake, to: "chat_wakes#show"
      post :logs, to: "agent_logs#create"
      post :register, to: "registrations#upsert"



      resources :objectives, only: [] do
        resources :research_snapshots, only: [:index, :create]
      end
    end
  end
end
