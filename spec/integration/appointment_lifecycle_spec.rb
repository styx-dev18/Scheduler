require "swagger_helper"

RSpec.describe "/api/v1/appointments lifecycle" do
  error_schema = {
    type: :object,
    properties: { success: { type: :boolean }, error: { "$ref" => "#/components/schemas/Error" } },
    required: %w[success error]
  }

  lifecycle_properties = {
    id: { type: :string, format: :uuid },
    status: { type: :string, enum: %w[confirmed in_progress completed cancelled no_show] },
    start_at: { type: :string, format: "date-time" },
    end_at: { type: :string, format: "date-time" },
    lock_version: { type: :integer },
    cancelled_at: { type: :string, format: "date-time", nullable: true },
    cancellation_reason: { type: :string, nullable: true }
  }
  appointment_envelope = {
    type: :object,
    properties: {
      success: { type: :boolean },
      data: { type: :object, properties: lifecycle_properties, required: %w[id status lock_version] }
    },
    required: %w[success data]
  }
  appointment_example = {
    success: true,
    data: {
      id: "6f1c2a3e-8d4b-4e5f-9a60-1b2c3d4e5f60",
      status: "cancelled",
      start_at: "2030-01-07T09:00:00Z",
      end_at: "2030-01-07T10:00:00Z",
      lock_version: 1,
      cancelled_at: "2030-01-01T00:00:00Z",
      cancellation_reason: "Change of plans"
    }
  }

  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let(:bay) { create(:service_bay, dealership:) }
  let(:tech) { create(:technician, dealership:) }
  let(:appointment) do
    create(:appointment, dealership:, customer:, vehicle:, technician: tech, service_bay: bay, service_type:)
  end
  let(:id) { appointment.id }
  let(:unknown_id) { "00000000-0000-0000-0000-000000000000" }

  before do
    travel_to Time.utc(2030, 1, 1)
    [ 1, 2 ].each do |day|
      create(:dealership_opening_hour, dealership:, day_of_week: day)
      create(:technician_shift, technician: tech, day_of_week: day)
    end
    create(:technician_qualification, technician: tech, qualification:)
  end

  path "/api/v1/appointments/{id}/cancel" do
    post "Cancel an appointment" do
      tags "Appointments"
      consumes "application/json"
      produces "application/json"
      parameter name: :id, in: :path, type: :string, format: :uuid
      parameter name: :payload, in: :body, required: false, schema: {
        type: :object,
        properties: { reason: { type: :string, maxLength: 500 } }
      }

      let(:payload) { { reason: "Change of plans" } }

      response "200", "AC1 appointment cancelled" do
        schema appointment_envelope
        example "application/json", :cancelled, appointment_example

        run_test! do |response|
          data = JSON.parse(response.body)["data"]
          expect(data).to include("status" => "cancelled", "cancellation_reason" => "Change of plans")
        end
      end

      response "400", "EC2 malformed id" do
        schema error_schema
        let(:id) { "nope" }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["errors"]).to eq({ "id" => [ "is not a valid UUID" ] })
        end
      end

      response "404", "EC2 unknown id" do
        schema error_schema
        let(:id) { unknown_id }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("APPOINTMENT_NOT_FOUND")
        end
      end

      response "409", "EC1 appointment can no longer be cancelled" do
        schema error_schema
        before { appointment.update!(status: "completed") }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to include("code" => "INVALID_STATUS_TRANSITION",
                                                                "allowed_transitions" => [])
        end
      end

      response "422", "EC4 cancellation window closed" do
        schema error_schema

        around do |example|
          previous = ENV["CANCELLATION_CUTOFF_HOURS"]
          ENV["CANCELLATION_CUTOFF_HOURS"] = "2000"
          example.run
        ensure
          ENV["CANCELLATION_CUTOFF_HOURS"] = previous
        end

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("CANCELLATION_WINDOW_CLOSED")
        end
      end
    end
  end

  path "/api/v1/appointments/{id}/reschedule" do
    post "Reschedule a confirmed appointment" do
      tags "Appointments"
      consumes "application/json"
      produces "application/json"
      parameter name: :id, in: :path, type: :string, format: :uuid
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          new_start_at: { type: :string, format: "date-time" },
          lock_version: { type: :integer }
        },
        required: %w[new_start_at]
      }

      let(:payload) { { new_start_at: "2030-01-08T11:00:00Z", lock_version: 0 } }

      response "200", "AC4 appointment rescheduled" do
        schema appointment_envelope
        example "application/json", :rescheduled,
                appointment_example.deep_merge(data: { status: "confirmed", start_at: "2030-01-08T11:00:00Z",
                                                       end_at: "2030-01-08T12:00:00Z", cancelled_at: nil,
                                                       cancellation_reason: nil })

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]).to include("start_at" => "2030-01-08T11:00:00Z", "lock_version" => 1)
        end
      end

      response "400", "EC5 invalid request" do
        schema error_schema
        let(:payload) { {} }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["errors"]).to have_key("new_start_at")
        end
      end

      response "404", "EC2 unknown id" do
        schema error_schema
        let(:id) { unknown_id }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("APPOINTMENT_NOT_FOUND")
        end
      end

      response "409", "EC7 stale lock_version" do
        schema error_schema
        before { appointment.update!(updated_at: Time.utc(2030, 1, 1, 1)) }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("CONCURRENT_MODIFICATION")
        end
      end

      response "422", "EC5 start time in the past" do
        schema error_schema
        let(:payload) { { new_start_at: "2029-12-31T09:00:00Z" } }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("START_TIME_IN_PAST")
        end
      end
    end
  end

  path "/api/v1/appointments/{id}/status" do
    patch "Move an appointment through the workshop statuses" do
      tags "Appointments"
      consumes "application/json"
      produces "application/json"
      parameter name: :id, in: :path, type: :string, format: :uuid
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { status: { type: :string, enum: %w[in_progress completed no_show] } },
        required: %w[status]
      }

      let(:payload) { { status: "in_progress" } }

      response "200", "AC8 status changed" do
        schema appointment_envelope
        example "application/json", :in_progress,
                appointment_example.deep_merge(data: { status: "in_progress", cancelled_at: nil,
                                                       cancellation_reason: nil })

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]["status"]).to eq("in_progress")
        end
      end

      response "400", "EC12 unsupported status" do
        schema error_schema
        let(:payload) { { status: "bogus" } }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["errors"]).to have_key("status")
        end
      end

      response "404", "EC12 unknown id" do
        schema error_schema
        let(:id) { unknown_id }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["code"]).to eq("APPOINTMENT_NOT_FOUND")
        end
      end

      response "409", "EC11 invalid transition" do
        schema error_schema
        let(:payload) { { status: "completed" } }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to include("code" => "INVALID_STATUS_TRANSITION",
                                                                "allowed_transitions" => %w[in_progress cancelled no_show])
        end
      end
    end
  end
end
