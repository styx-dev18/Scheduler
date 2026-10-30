require "swagger_helper"

RSpec.describe "POST /api/v1/appointments" do
  error_schema = {
    type: :object,
    properties: { success: { type: :boolean }, error: { type: :object } },
    required: %w[success error]
  }

  path "/api/v1/appointments" do
    post "Book an appointment" do
      tags "Appointments"
      consumes "application/json"
      produces "application/json"
      parameter name: :"Idempotency-Key", in: :header, type: :string, required: false
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          customer_id: { type: :string, format: :uuid },
          vehicle_id: { type: :string, format: :uuid },
          service_type_id: { type: :string, format: :uuid },
          dealership_id: { type: :string, format: :uuid },
          start_at: { type: :string, format: "date-time" }
        },
        required: %w[customer_id vehicle_id service_type_id dealership_id start_at]
      }

      let(:dealership) { create(:dealership) }
      let(:qualification) { create(:qualification) }
      let(:service_type) { create(:service_type, required_qualification: qualification) }
      let(:customer) { create(:customer) }
      let(:vehicle) { create(:vehicle, customer:) }
      let(:unknown_id) { "00000000-0000-4000-8000-000000000000" }
      let(:"Idempotency-Key") { nil }
      let(:payload) do
        {
          customer_id: customer.id,
          vehicle_id: vehicle.id,
          service_type_id: service_type.id,
          dealership_id: dealership.id,
          start_at: "2030-01-07T09:00:00Z"
        }
      end
      before do
        travel_to Time.utc(2030, 1, 1)
        create(:dealership_opening_hour, dealership:)
        technician = create(:technician, dealership:)
        create(:service_bay, dealership:)
        create(:technician_qualification, technician:, qualification:)
        create(:technician_shift, technician:)
      end

      response "201", "appointment booked" do
        schema type: :object,
               properties: { success: { type: :boolean }, data: { type: :object } },
               required: %w[success data]

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]["status"]).to eq("confirmed")
        end
      end

      response "400", "malformed request" do
        schema error_schema
        let(:payload) { super().except(:vehicle_id) }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("VALIDATION_ERROR")
        end
      end

      response "404", "unknown resource" do
        schema error_schema
        let(:payload) { super().merge(dealership_id: unknown_id) }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["detail"]).to eq("Dealership not found")
        end
      end

      response "409", "vehicle already booked" do
        schema error_schema

        before { create(:appointment, dealership:, customer:, vehicle:, service_type:) }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("VEHICLE_ALREADY_BOOKED")
        end
      end

      response "422", "outside opening hours" do
        schema error_schema
        let(:payload) { super().merge(start_at: "2030-01-07T16:15:00Z") }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("OUTSIDE_OPENING_HOURS")
        end
      end
    end
  end
end
