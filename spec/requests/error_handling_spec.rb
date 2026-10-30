require "rails_helper"

class ErrorHandlingProbeController < Api::V1::BaseController
  def not_found
    raise ActiveRecord::RecordNotFound, "Couldn't find Thing"
  end

  def missing_param
    params.require(:widget)
  end

  def invalid
    record = Class.new do
      include ActiveModel::Model
      attr_accessor :name

      validates :name, presence: true

      def self.name = "Widget"
    end.new
    record.validate
    raise ActiveRecord::RecordInvalid, record
  end

  def stale
    raise ActiveRecord::StaleObjectError.new(nil, "update")
  end

  def with_extra
    render_failure("NO_BAY", detail: "No bay", extra: { starts_at: "2030-01-07T09:00:00Z", ends_at: "2030-01-07T10:00:00Z" })
  end

  def bad_page
    pagy(Dealership.all, page: 0)
  end

  def boom
    raise "secret internal failure"
  end
end

RSpec.describe "BaseController error handling" do
  before do
    Rails.application.routes.draw do
      get "probe/not_found" => "error_handling_probe#not_found"
      get "probe/missing_param" => "error_handling_probe#missing_param"
      get "probe/invalid" => "error_handling_probe#invalid"
      get "probe/stale" => "error_handling_probe#stale"
      get "probe/with_extra" => "error_handling_probe#with_extra"
      get "probe/bad_page" => "error_handling_probe#bad_page"
      get "probe/boom" => "error_handling_probe#boom"
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
    expect(body["error"]["status"]).to eq(Rack::Utils::SYMBOL_TO_STATUS_CODE[status] || status)
    expect(body["message"]).to eq(body["error"]["detail"])
    body
  end

  it "AC7 maps RecordNotFound to 404 NOT_FOUND" do
    get "/probe/not_found"

    expect_envelope(status: 404, code: "NOT_FOUND")
  end

  it "AC7 maps ParameterMissing to 400 naming the parameter" do
    get "/probe/missing_param"

    body = expect_envelope(status: 400, code: "VALIDATION_ERROR")
    expect(body["error"]["errors"]).to eq("widget" => [ "is required" ])
    expect(body["error"]["detail"]).to include("widget")
  end

  it "AC7 maps RecordInvalid to 422 with field errors" do
    get "/probe/invalid"

    body = expect_envelope(status: 422, code: "VALIDATION_ERROR")
    expect(body["error"]["errors"]).to eq("name" => [ "can't be blank" ])
  end

  it "AC7 maps StaleObjectError to 409 CONCURRENT_MODIFICATION" do
    get "/probe/stale"

    expect_envelope(status: 409, code: "CONCURRENT_MODIFICATION")
  end

  it "merges extra into the error object" do
    get "/probe/with_extra"

    body = expect_envelope(status: 409, code: "NO_BAY")
    expect(body["error"]).to include("starts_at" => "2030-01-07T09:00:00Z", "ends_at" => "2030-01-07T10:00:00Z")
  end

  it "maps Pagy::VariableError to 400 VALIDATION_ERROR on page" do
    get "/probe/bad_page"

    body = expect_envelope(status: 400, code: "VALIDATION_ERROR")
    expect(body["error"]["errors"]).to eq("page" => [ "is invalid" ])
  end

  it "AC7 maps unexpected errors to 500 without leaking a backtrace" do
    get "/probe/boom"

    expect_envelope(status: 500, code: "INTERNAL_ERROR")
    expect(response.body).not_to include("secret internal failure")
    expect(response.body).not_to match(/\.rb:\d+/)
    expect(response.parsed_body["error"]).not_to have_key("backtrace")
  end
end
