require "rails_helper"

RSpec.describe "CORS" do
  it "AC8 sets Access-Control-Allow-Origin for an allowed origin" do
    get "/health", headers: { "Origin" => "http://localhost:3000" }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:3000")
  end

  it "AC8 answers a preflight request for an allowed origin" do
    options "/health", headers: {
      "Origin" => "http://localhost:3000",
      "Access-Control-Request-Method" => "GET"
    }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:3000")
  end
end
