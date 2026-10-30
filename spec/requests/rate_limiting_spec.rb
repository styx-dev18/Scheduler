require "rails_helper"

RSpec.describe "Rate limiting" do
  around do |example|
    original_enabled = Rack::Attack.enabled
    original_store = Rack::Attack.cache.store
    original_env = ENV.to_h.slice("RATE_LIMIT_REQUESTS", "RATE_LIMIT_BOOKING_REQUESTS")
    ENV["RATE_LIMIT_REQUESTS"] = "4"
    ENV["RATE_LIMIT_BOOKING_REQUESTS"] = "2"
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    example.run
  ensure
    Rack::Attack.enabled = original_enabled
    Rack::Attack.cache.store = original_store
    %w[RATE_LIMIT_REQUESTS RATE_LIMIT_BOOKING_REQUESTS].each { |key| ENV.delete(key) }
    original_env.each { |key, value| ENV[key] = value }
  end

  def expect_rate_limited
    body = response.parsed_body
    expect(response).to have_http_status(429)
    expect(response.headers["Content-Type"]).to include("application/json")
    expect(body.keys).to match_array(%w[success data error message])
    expect(body["success"]).to be(false)
    expect(body["data"]).to be_nil
    expect(body["error"]).to include("type", "title", "status", "code", "detail")
    expect(body["error"]["code"]).to eq("RATE_LIMITED")
    expect(body["error"]["status"]).to eq(429)
    expect(body["message"]).to eq(body["error"]["detail"])
    expect(response.headers["Retry-After"].to_i).to be_between(1, 60)
    expect(body["error"]["detail"]).to include(response.headers["Retry-After"])
  end

  it "AC1 returns 429 RATE_LIMITED with Retry-After once the general limit is exceeded" do
    4.times { get "/api/v1/dealerships" }
    expect(response).not_to have_http_status(429)

    get "/api/v1/dealerships"

    expect_rate_limited
  end

  it "AC2 returns 429 RATE_LIMITED with Retry-After once the booking limit is exceeded" do
    2.times do
      post "/api/v1/appointments", params: {}
      expect(response).not_to have_http_status(429)
    end

    post "/api/v1/appointments", params: {}

    expect_rate_limited
  end

  it "AC2 applies the booking limit to POST only, leaving GET on the general limit" do
    3.times { post "/api/v1/appointments", params: {} }

    get "/api/v1/appointments"

    expect(response).not_to have_http_status(429)
  end

  it "AC3 never throttles /up, /health, /health/live or /health/ready" do
    aggregate_failures do
      %w[/up /health /health/live /health/ready].each do |path|
        10.times do
          get path
          expect(response).not_to have_http_status(429), "#{path} was throttled"
        end
      end
    end
  end

  it "AC3 does not count safelisted requests toward the general limit" do
    10.times { get "/health" }

    get "/api/v1/dealerships"

    expect(response).not_to have_http_status(429)
  end

  it "AC1 does not throttle when disabled" do
    Rack::Attack.enabled = false

    10.times { get "/api/v1/dealerships" }

    expect(response).not_to have_http_status(429)
  end
end
