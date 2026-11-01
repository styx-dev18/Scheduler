Rails.application.routes.draw do
  if ENV["DOCS_ENABLED"] == "true"
    mount Rswag::Ui::Engine => "/api-docs"
    mount Rswag::Api::Engine => "/api-docs"
  end

  if ENV["METRICS_ENABLED"] == "true"
    mount MetricsAuthentication.new(Yabeda::Prometheus::Exporter) => "/metrics"
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show"
  get "health/live" => "health#show"
  get "health/ready" => "health#ready"

  namespace :api do
    namespace :v1 do
      resources :dealerships, only: :index do
        resources :appointments, only: :index, controller: "dealership_appointments"
      end
      resources :service_types, path: "service-types", only: :index
      resources :appointments, only: %i[create show index] do
        member do
          post :cancel
          post :reschedule
          patch :status, action: :update_status
        end
      end
      get "availability", to: "availability#index"
    end
  end
end
