Rails.application.routes.draw do
  if ENV["DOCS_ENABLED"] == "true"
    mount Rswag::Ui::Engine => "/api-docs"
    mount Rswag::Api::Engine => "/api-docs"
  end

  if ENV["METRICS_ENABLED"] == "true"
    metrics_app = lambda do |env|
      token = ENV["METRICS_TOKEN"].presence
      supplied = env["HTTP_AUTHORIZATION"].to_s.delete_prefix("Bearer ")
      if token.nil? || ActiveSupport::SecurityUtils.secure_compare(supplied, token)
        Yabeda::Prometheus::Exporter.call(env)
      else
        entry = ErrorCatalogue.fetch("UNAUTHORIZED")
        detail = "Invalid or missing metrics token"
        body = {
          success: false, data: nil,
          error: { type: "https://httpstatuses.com/#{entry.status}", title: entry.title, status: entry.status,
                   code: entry.code, detail: detail },
          message: detail
        }
        [ entry.status, { "content-type" => "application/json", "www-authenticate" => "Bearer" }, [ body.to_json ] ]
      end
    end
    mount metrics_app => "/metrics"
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
