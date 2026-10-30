Rails.application.routes.draw do
  if ENV["DOCS_ENABLED"] == "true"
    mount Rswag::Ui::Engine => "/api-docs"
    mount Rswag::Api::Engine => "/api-docs"
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show"

  namespace :api do
    namespace :v1 do
      resources :dealerships, only: :index
      resources :service_types, path: "service-types", only: :index
      resources :appointments, only: :create
      get "availability", to: "availability#index"
    end
  end
end
