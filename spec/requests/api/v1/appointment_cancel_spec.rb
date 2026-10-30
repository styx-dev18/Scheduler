require "rails_helper"

RSpec.describe "POST /api/v1/appointments/:id/cancel" do
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }
  let!(:appointment) do
    create(:appointment, dealership:, customer:, vehicle:, technician: tech, service_bay: bay, service_type:)
  end
  let(:body) { response.parsed_body }
  let(:events) { [] }

  before do
    travel_to Time.utc(2030, 1, 1)
    create(:dealership_opening_hour, dealership:)
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  def cancel(id = appointment.id, params = {})
    post "/api/v1/appointments/#{id}/cancel", params:
  end

  def capture_events(&block)
    subscriber = ActiveSupport::Notifications.subscribe(/\Aappointment\./) { |event| events << event }
    block.call
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "AC1 cancels, records history and frees the slot for a new booking" do
    cancel(appointment.id, { reason: "ac1" })

    expect(response).to have_http_status(:ok)
    aggregate_failures do
      expect(body["success"]).to be(true)
      expect(body["error"]).to be_nil
      expect(body["data"]).to include("id" => appointment.id, "status" => "cancelled",
                                      "cancelled_at" => "2030-01-01T00:00:00Z", "cancellation_reason" => "ac1")
      history = appointment.status_histories.sole
      expect([ history.from_status, history.to_status, history.actor ]).to eq(%w[confirmed cancelled customer])
    end

    post "/api/v1/appointments", params: {
      customer_id: customer.id, vehicle_id: vehicle.id, service_type_id: service_type.id,
      dealership_id: dealership.id, start_at: "2030-01-07T09:00:00Z"
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["data"]).to include("id" => satisfy { |id| id != appointment.id },
                                                     "service_bay_id" => bay.id, "technician_id" => tech.id)
  end

  it "AC2 returns the same data on a repeat cancel with one history row and one event" do
    capture_events do
      cancel(appointment.id, { reason: "ac2" })
      first = response.parsed_body["data"]
      cancel(appointment.id, { reason: "ac2" })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to eq(first)
    end

    expect(appointment.status_histories.count).to eq(1)
    expect(events.map(&:name)).to eq([ "appointment.cancelled" ])
  end

  it "EC1 rejects cancelling a completed appointment with an empty allowed list" do
    appointment.update!(status: "completed")

    capture_events { cancel }

    expect(response).to have_http_status(:conflict)
    expect(body["success"]).to be(false)
    expect(body["data"]).to be_nil
    expect(body["error"]).to include("code" => "INVALID_STATUS_TRANSITION", "allowed_transitions" => [])
    expect(appointment.reload.status).to eq("completed")
    expect(appointment.status_histories.count).to eq(0)
    expect(events).to be_empty
  end

  it "EC2 returns 404 for an unknown id" do
    cancel("00000000-0000-0000-0000-000000000000")

    expect(response).to have_http_status(:not_found)
    expect(body["error"]["code"]).to eq("APPOINTMENT_NOT_FOUND")
  end

  it "EC2 returns 400 for a malformed id" do
    cancel("nope")

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]).to include("code" => "VALIDATION_ERROR", "errors" => { "id" => [ "is not a valid UUID" ] })
  end

  it "EC3 rejects a 501-character reason, accepts none and accepts exactly 500" do
    cancel(appointment.id, { reason: "a" * 501 })

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["errors"]).to have_key("reason")
    expect(appointment.reload.status).to eq("confirmed")

    cancel(appointment.id, { reason: "a" * 500 })

    expect(response).to have_http_status(:ok)
    expect(appointment.reload.cancellation_reason).to eq("a" * 500)
  end

  it "EC3 rejects a non-string reason with 400 VALIDATION_ERROR" do
    post "/api/v1/appointments/#{appointment.id}/cancel", params: { reason: 123 }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["errors"]).to eq({ "reason" => [ "must be a string" ] })
    expect(appointment.reload.status).to eq("confirmed")
  end

  it "EC3 accepts a cancel with no body and a null reason" do
    cancel

    expect(response).to have_http_status(:ok)
    expect(body["data"]["cancellation_reason"]).to be_nil
    expect(body["data"]["status"]).to eq("cancelled")
  end
end
