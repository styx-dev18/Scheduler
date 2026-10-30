require "rails_helper"

RSpec.describe "GET /health" do
  it "AC1 returns 200 in the envelope" do
    get "/health"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "success" => true, "data" => { "status" => "ok" }, "error" => nil, "message" => nil
    )
  end
end
