Rails.application.routes.draw do
  get "/healthz", to: "health#show"
end
