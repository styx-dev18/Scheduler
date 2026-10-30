require "rails_helper"
require "open3"

class TracingProbeController < Api::V1::BaseController
  def show
    render json: { trace_id: Current.trace_id, request_id: Current.request_id }
  end
end

RSpec.describe "Tracing" do
  include_context "with in-memory tracing"

  before do
    Rails.application.routes.draw { get "probe/trace" => "tracing_probe#show" }
  end

  after { Rails.application.reload_routes! }

  it "AC-trace leaves Current.trace_id nil and succeeds with the default tracer" do
    get "/probe/trace"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("trace_id" => nil)
    expect(response.parsed_body["request_id"]).to be_present
  end

  it "AC-trace sets Current.trace_id to the 32-hex trace id of a valid span context" do
    trace_id = nil

    test_tracer.in_span("request") do |span|
      trace_id = span.context.hex_trace_id
      get "/probe/trace"
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["trace_id"]).to match(/\A\h{32}\z/).and eq(trace_id)
  end
end

RSpec.describe "Tracing configuration" do
  it "AC-trace serves real endpoints with tracing disabled" do
    get "/health"

    expect(response).to have_http_status(:ok)
  end

  it "AC-trace does not configure the SDK tracer provider when OTEL_ENABLED is not true" do
    expect(ENV["OTEL_ENABLED"]).not_to eq("true")
    expect(OpenTelemetry.tracer_provider).to be_a(OpenTelemetry::Internal::ProxyTracerProvider)
  end
end

RSpec.describe "OpenTelemetry boot" do
  it "AC-trace boots with OTEL_ENABLED=true and installs a real tracer provider" do
    script = 'exit(OpenTelemetry.tracer_provider.is_a?(OpenTelemetry::SDK::Trace::TracerProvider) ? 0 : 1)'
    env = { "OTEL_ENABLED" => "true", "RAILS_ENV" => "test", "OTEL_TRACES_EXPORTER" => "none" }

    _, status = Open3.capture2e(env, Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s)

    expect(status.exitstatus).to eq(0)
  end
end
