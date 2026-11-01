require "swagger_helper"

RSpec.describe "GET /api/v1/dealerships/{dealership_id}/appointments" do
  path "/api/v1/dealerships/{dealership_id}/appointments" do
    get "List a dealership's appointments" do
      tags "Dealerships"
      produces "application/json"
      parameter name: :dealership_id, in: :path, type: :string, format: :uuid
      parameter name: :date, in: :query, type: :string, format: :date, required: false
      parameter name: :technician_id, in: :query, type: :string, format: :uuid, required: false
      parameter name: :service_bay_id, in: :query, type: :string, format: :uuid, required: false
      parameter name: :status, in: :query, type: :string, required: false,
                enum: %w[confirmed in_progress completed cancelled no_show]
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false

      let(:dealership) { create(:dealership) }
      let(:dealership_id) { dealership.id }

      response "200", "schedule for the dealership" do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array, items: { type: :object } },
                 meta: { type: :object }
               },
               required: %w[success data meta]

        let(:date) { "2030-01-07" }

        before do
          create(:appointment, dealership:, start_at: Time.utc(2030, 1, 7, 9), end_at: Time.utc(2030, 1, 7, 10))
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["data"].size).to eq(1)
          expect(body["meta"]).to include("page" => 1, "total_count" => 1)
        end
      end

      response "400", "malformed dealership id" do
        schema "$ref" => "#/components/schemas/Envelope"
        let(:dealership_id) { "nope" }

        run_test! do |response|
          error = JSON.parse(response.body)["error"]
          expect(error["code"]).to eq("VALIDATION_ERROR")
          expect(error["errors"]).to have_key("dealership_id")
        end
      end

      response "404", "unknown dealership" do
        schema "$ref" => "#/components/schemas/Envelope"
        let(:dealership_id) { "00000000-0000-4000-8000-000000000000" }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("NOT_FOUND")
        end
      end
    end
  end
end
