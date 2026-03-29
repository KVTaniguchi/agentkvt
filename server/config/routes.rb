Rails.application.routes.draw do
  get "/healthz", to: "health#show"

  namespace :v1 do
    post :chat_wake, to: "chat_wakes#create"

    resource :bootstrap, only: :show
    resources :family_members, only: [:index, :create]
    resources :missions, only: [:index, :create, :update, :destroy] do
      post :run_now, on: :member
    end
    resources :life_context, only: [:index, :update], controller: "life_context_entries", param: :key
    resources :action_items, only: [:index] do
      post :handle, on: :member
    end
    resources :agent_logs, only: [:index]
    resources :objectives, only: [:index, :create, :show, :update, :destroy]

    namespace :agent do
      get :due_missions, to: "due_missions#index"
      get :chat_wake, to: "chat_wakes#show"

      resources :missions, only: [] do
        get :action_items, to: "mission_action_items#index"
        post :action_items, to: "mission_action_items#create"
        get :logs, to: "mission_logs#index"
        post :logs, to: "mission_logs#create"
        post :mark_run, to: "mission_runs#create"
      end

      resources :objectives, only: [] do
        resources :research_snapshots, only: [:create]
      end
    end
  end
end
