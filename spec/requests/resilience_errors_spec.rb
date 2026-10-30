require "rails_helper"

class ResilienceProbeController < Api::V1::BaseController
  def query_canceled
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = 50")
      ActiveRecord::Base.connection.execute("SELECT pg_sleep(2)")
    end
  end

  def request_timeout
    ActiveRecord::Base.transaction(requires_new: true) do
      raise Rack::Timeout::RequestTimeoutException, request.env
    end
  end

  def not_established
    raise ActiveRecord::ConnectionNotEstablished, "no connection"
  end

  def pool_timeout
    raise ActiveRecord::ConnectionTimeoutError, "could not obtain a connection from the pool"
  end
end

RSpec.describe "Resilience error handling" do
  before do
    Rails.application.routes.draw do
      get "probe/query_canceled" => "resilience_probe#query_canceled"
      get "probe/request_timeout" => "resilience_probe#request_timeout"
      get "probe/not_established" => "resilience_probe#not_established"
      get "probe/pool_timeout" => "resilience_probe#pool_timeout"
    end
  end

  after { Rails.application.reload_routes! }

  def expect_envelope(status:, code:)
    body = response.parsed_body
    expect(response).to have_http_status(status)
    expect(body.keys).to match_array(%w[success data error message])
    expect(body["success"]).to be(false)
    expect(body["data"]).to be_nil
    expect(body["error"]).to include("type", "title", "status", "code", "detail")
    expect(body["error"]["code"]).to eq(code)
    expect(body["error"]["status"]).to eq(status)
    expect(body["message"]).to eq(body["error"]["detail"])
    body
  end

  it "AC4 maps a PostgreSQL statement timeout to 504 REQUEST_TIMEOUT" do
    get "/probe/query_canceled"

    expect_envelope(status: 504, code: "REQUEST_TIMEOUT")
  end

  it "AC4 maps Rack::Timeout::RequestTimeoutException to 504 REQUEST_TIMEOUT" do
    get "/probe/request_timeout"

    expect_envelope(status: 504, code: "REQUEST_TIMEOUT")
  end

  it "AC4 leaves no open transaction and a usable connection after a statement timeout" do
    before_depth = ActiveRecord::Base.connection.open_transactions

    get "/probe/query_canceled"

    expect(ActiveRecord::Base.connection.open_transactions).to eq(before_depth)
    expect(ActiveRecord::Base.connection.select_value("SHOW statement_timeout")).not_to eq("50ms")
    expect(Dealership.count).to be >= 0
  end

  it "AC4 leaves no open transaction after a rack timeout" do
    before_depth = ActiveRecord::Base.connection.open_transactions

    get "/probe/request_timeout"

    expect(ActiveRecord::Base.connection.open_transactions).to eq(before_depth)
  end

  it "AC5 maps ConnectionNotEstablished to 503 SERVICE_UNAVAILABLE" do
    get "/probe/not_established"

    body = expect_envelope(status: 503, code: "SERVICE_UNAVAILABLE")
    expect(response.body).not_to include("no connection")
    expect(body["error"]["detail"]).to eq("The service is temporarily unavailable")
  end

  it "AC5 maps ConnectionTimeoutError to 503 SERVICE_UNAVAILABLE" do
    get "/probe/pool_timeout"

    body = expect_envelope(status: 503, code: "SERVICE_UNAVAILABLE")
    expect(response.body).not_to include("pool")
    expect(body["error"]["detail"]).to eq("The service is temporarily unavailable")
  end
end
