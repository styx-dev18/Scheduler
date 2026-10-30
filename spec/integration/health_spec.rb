require "swagger_helper"

RSpec.describe "GET /health" do
  path "/health" do
    get "Health check" do
      tags "Health"
      produces "application/json"

      response "200", "AC10 service is healthy" do
        schema "$ref" => "#/components/schemas/Envelope"

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]).to eq("status" => "ok")
        end
      end
    end
  end
end
