require "swagger_helper"

RSpec.describe "/api/v1/appointments" do
  error_schema = {
    type: :object,
    properties: { success: { type: :boolean }, error: { type: :object } },
    required: %w[success error]
  }

  appointment_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      status: { type: :string, enum: %w[confirmed cancelled] },
      customer_id: { type: :string, format: :uuid },
      vehicle_id: { type: :string, format: :uuid },
      service_type_id: { type: :string, format: :uuid },
      dealership_id: { type: :string, format: :uuid },
      technician_id: { type: :string, format: :uuid },
      service_bay_id: { type: :string, format: :uuid },
      start_at: { type: :string, format: "date-time" },
      end_at: { type: :string, format: "date-time" },
      local_start_at: { type: :string, format: "date-time" },
      local_end_at: { type: :string, format: "date-time" },
      time_zone: { type: :string },
      customer: { type: :object, properties: { id: { type: :string }, name: { type: :string } } },
      vehicle: {
        type: :object,
        properties: { id: { type: :string }, make: { type: :string }, model: { type: :string },
                      year: { type: :integer, nullable: true }, license_plate: { type: :string, nullable: true } }
      },
      service_type: {
        type: :object,
        properties: { id: { type: :string }, name: { type: :string }, duration_minutes: { type: :integer } }
      },
      dealership: { type: :object, properties: { id: { type: :string }, name: { type: :string } } },
      technician: { type: :object, properties: { id: { type: :string }, display_name: { type: :string } } },
      service_bay: { type: :object, properties: { id: { type: :string }, label: { type: :string } } }
    },
    required: %w[id status customer_id vehicle_id service_type_id dealership_id technician_id service_bay_id start_at
                 end_at local_start_at local_end_at time_zone customer vehicle service_type dealership technician
                 service_bay]
  }
  appointment_example = {
    success: true,
    data: {
      id: "6f1c2a3e-8d4b-4e5f-9a60-1b2c3d4e5f60",
      status: "confirmed",
      customer_id: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
      vehicle_id: "1b2c3d4e-5f60-4b7c-9d8e-0f1a2b3c4d5e",
      service_type_id: "2c3d4e5f-6071-4c8d-8e9f-1a2b3c4d5e6f",
      dealership_id: "3d4e5f60-7182-4d9e-9fa0-2b3c4d5e6f70",
      technician_id: "4e5f6071-8293-4eaf-8ab1-3c4d5e6f7081",
      service_bay_id: "5f607182-93a4-4fb0-9bc2-4d5e6f708192",
      start_at: "2030-01-07T09:00:00Z",
      end_at: "2030-01-07T10:00:00Z",
      local_start_at: "2030-01-07T09:00:00+00:00",
      local_end_at: "2030-01-07T10:00:00+00:00",
      time_zone: "Europe/London",
      customer: { id: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", name: "Alex Morgan" },
      vehicle: { id: "1b2c3d4e-5f60-4b7c-9d8e-0f1a2b3c4d5e", make: "Toyota", model: "Corolla", year: 2021,
                 license_plate: "AB12 CDE" },
      service_type: { id: "2c3d4e5f-6071-4c8d-8e9f-1a2b3c4d5e6f", name: "Annual service", duration_minutes: 60 },
      dealership: { id: "3d4e5f60-7182-4d9e-9fa0-2b3c4d5e6f70", name: "Central Motors" },
      technician: { id: "4e5f6071-8293-4eaf-8ab1-3c4d5e6f7081", display_name: "Sam Taylor" },
      service_bay: { id: "5f607182-93a4-4fb0-9bc2-4d5e6f708192", label: "Bay 1" }
    }
  }
  appointment_envelope = {
    type: :object,
    properties: { success: { type: :boolean }, data: appointment_schema },
    required: %w[success data]
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
      let(:vehicle) { create(:vehicle, customer:, year: 2021, license_plate: "AB12 CDE") }
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

      response "201", "AC4 appointment confirmed" do
        schema appointment_envelope
        header "Location", schema: { type: :string }, description: "URL of GET /api/v1/appointments/{id}"
        example "application/json", :confirmed, appointment_example

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["data"]["status"]).to eq("confirmed")
          expect(response.headers["Location"]).to end_with("/api/v1/appointments/#{body['data']['id']}")
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

  path "/api/v1/appointments/{id}" do
    get "Retrieve a confirmed appointment" do
      tags "Appointments"
      produces "application/json"
      parameter name: :id, in: :path, type: :string, format: :uuid

      let(:appointment) do
        customer = create(:customer)
        create(:appointment, customer:, vehicle: create(:vehicle, customer:, year: 2021, license_plate: "AB12 CDE"))
      end
      let(:id) { appointment.id }

      response "200", "AC6 appointment found" do
        schema appointment_envelope
        example "application/json", :found, appointment_example

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]["id"]).to eq(appointment.id)
        end
      end

      response "400", "EC5 malformed id" do
        schema error_schema
        let(:id) { "not-a-uuid" }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["errors"]).to eq({ "id" => [ "is not a valid UUID" ] })
        end
      end

      response "404", "EC4 unknown id" do
        schema error_schema
        let(:id) { "00000000-0000-0000-0000-000000000000" }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("APPOINTMENT_NOT_FOUND")
        end
      end
    end
  end
end
