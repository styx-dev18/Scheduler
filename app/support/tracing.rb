module Tracing
  module_function

  def tracer(scope)
    OpenTelemetry.tracer_provider.tracer(scope)
  end

  def in_span(name, scope:, dealership:, service_type:, &block)
    attributes = { "dealership.id" => dealership.id, "service_type.id" => service_type.id }
    tracer(scope).in_span(name, attributes:, &block)
  end
end
