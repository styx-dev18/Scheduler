if ENV["OTEL_ENABLED"] == "true"
  OpenTelemetry::SDK.configure do |config|
    config.service_name = ENV.fetch("OTEL_SERVICE_NAME", "scheduler-api")
    config.use "OpenTelemetry::Instrumentation::Rack"
    config.use "OpenTelemetry::Instrumentation::Rails"
    config.use "OpenTelemetry::Instrumentation::PG"
    config.use "OpenTelemetry::Instrumentation::ActiveRecord"
  end
end
