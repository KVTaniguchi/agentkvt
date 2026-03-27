Rails.application.routes.draw do
  get "/healthz", to: "health#show"

  namespace :v1 do
    resource :bootstrap, only: :show
    resources :family_members, only: [:index, :create]
    resources :missions, only: [:index, :create, :update, :destroy]
    resources :action_items, only: [:index] do
      post :handle, on: :member
    end
    resources :agent_logs, only: [:index]

    namespace :agent do
      get :due_missions, to: "due_missions#index"

      resources :missions, only: [] do
        post :action_items, to: "mission_action_items#create"
        post :logs, to: "mission_logs#create"
        post :mark_run, to: "mission_runs#create"
      end
    end
  end
end
