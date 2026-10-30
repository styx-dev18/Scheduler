require "swagger_helper"

RSpec.describe "GET /api/v1/availability" do
  error_schema = {
    type: :object,
    properties: { success: { type: :boolean }, error: { type: :object } },
    required: %w[success error]
  }

  path "/api/v1/availability" do
    get "List bookable start times for a day" do
      tags "Availability"
      produces "application/json"
      parameter name: :dealership_id, in: :query, type: :string, format: :uuid, required: true
      parameter name: :service_type_id, in: :query, type: :string, format: :uuid, required: true
      parameter name: :date, in: :query, type: :string, format: :date, required: true

      let(:dealership) { create(:dealership) }
      let(:qualification) { create(:qualification) }
      let(:service_type) { create(:service_type, required_qualification: qualification) }
      let(:dealership_id) { dealership.id }
      let(:service_type_id) { service_type.id }
      let(:date) { "2030-01-07" }

      before do
        travel_to Time.utc(2030, 1, 1)
        create(:dealership_opening_hour, dealership:)
        technician = create(:technician, dealership:)
        create(:service_bay, dealership:)
        create(:technician_qualification, technician:, qualification:)
        create(:technician_shift, technician:)
      end

      response "200", "bookable start times" do
        schema type: :object,
               properties: { success: { type: :boolean }, data: { type: :object } },
               required: %w[success data]

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]["slots"].first["start_at"]).to eq("2030-01-07T08:00:00Z")
        end
      end

      response "400", "invalid parameters" do
        schema error_schema
        let(:date) { "07/01/2030" }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("VALIDATION_ERROR")
        end
      end

      response "404", "unknown resource" do
        schema error_schema
        let(:dealership_id) { "00000000-0000-4000-8000-000000000000" }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("NOT_FOUND")
        end
      end
    end
  end
end
