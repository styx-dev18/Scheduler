require "rails_helper"

RSpec.describe "Request logging" do
  def capture_log_line(&request)
    payload = nil
    options = nil
    callback = lambda do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      payload = event.payload
      options = Rails.application.config.lograge.custom_options.call(event)
    end
    ActiveSupport::Notifications.subscribed(callback, "process_action.action_controller", &request)
    [ payload, JSON.parse(Rails.application.config.lograge.formatter.call(options)) ]
  end

  it "AC1 emits a JSON line with request_id, method, path, status and duration" do
    _payload, line = capture_log_line { get "/health", headers: { "X-Request-Id" => "req-log-1" } }

    expect(line).to include("request_id" => "req-log-1", "method" => "GET", "path" => "/health", "status" => 200)
    expect(line["duration"]).to be_a(Numeric)
  end

  it "AC1 drops nil attributes from the line" do
    _payload, line = capture_log_line { get "/health" }

    expect(line.keys).not_to include("trace_id", "appointment_id")
  end

  it "AC1 redacts sensitive parameters" do
    payload, line = capture_log_line do
      get "/health", params: { password: "hunter2", token: "tok-123", email: "a@example.test", note: "visible" }
    end

    expect(payload[:params]).to include(
      "password" => "[FILTERED]", "token" => "[FILTERED]", "email" => "[FILTERED]", "note" => "visible"
    )
    expect(line.to_json).not_to include("hunter2", "tok-123", "a@example.test")
  end

  it "AC1 does not log request bodies" do
    _payload, line = capture_log_line do
      post "/api/v1/appointments", params: { secret_note: "body-marker-xyz" }.to_json,
                                   headers: { "CONTENT_TYPE" => "application/json" }
    end

    expect(line.to_json).not_to include("body-marker-xyz")
    expect(line.keys).not_to include("body", "params")
  end

  it "AC1 enables Lograge with the JSON formatter in production" do
    expect(Rails.application.config.lograge.formatter).to be_a(Lograge::Formatters::Json)
  end
end
