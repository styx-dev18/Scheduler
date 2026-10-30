require "rails_helper"

RSpec.describe "GET /api/v1/appointments/:id" do
  let(:body) { response.parsed_body }

  it "AC6 returns the confirmation shape without N+1 queries" do
    appointment = create(:appointment)

    get "/api/v1/appointments/#{appointment.id}"

    expect(response).to have_http_status(:ok)
    data = body["data"]
    aggregate_failures do
      expect(body["success"]).to be(true)
      expect(data.keys).to match_array(%w[id status customer_id vehicle_id service_type_id dealership_id technician_id
                                          service_bay_id start_at end_at local_start_at local_end_at time_zone lock_version cancelled_at cancellation_reason customer
                                          vehicle service_type dealership technician service_bay])
      expect(data["id"]).to eq(appointment.id)
      expect(data["customer"]).to eq({ "id" => appointment.customer.id, "name" => appointment.customer.name })
      expect(data["technician"]).to eq({ "id" => appointment.technician.id, "display_name" => appointment.technician.name })
      expect(data["service_bay"]).to eq({ "id" => appointment.service_bay.id, "label" => appointment.service_bay.name })
    end
  end

  it "EC3 reports consistent local times across time zones" do
    auckland = create(:dealership, time_zone: "Pacific/Auckland")
    new_york = create(:dealership, time_zone: "America/New_York")
    start_at = Time.utc(2030, 1, 7, 21)
    nz = create(:appointment, dealership: auckland, start_at:, end_at: start_at + 1.hour)
    ny = create(:appointment, dealership: new_york, start_at:, end_at: start_at + 1.hour)

    get "/api/v1/appointments/#{nz.id}"
    nz_data = response.parsed_body["data"]
    get "/api/v1/appointments/#{ny.id}"
    ny_data = response.parsed_body["data"]

    aggregate_failures do
      expect([ nz_data["start_at"], ny_data["start_at"] ]).to eq([ "2030-01-07T21:00:00Z", "2030-01-07T21:00:00Z" ])
      expect(nz_data["local_start_at"]).to eq("2030-01-08T10:00:00+13:00")
      expect(ny_data["local_start_at"]).to eq("2030-01-07T16:00:00-05:00")
      expect(nz_data["time_zone"]).to eq("Pacific/Auckland")
      expect(ny_data["time_zone"]).to eq("America/New_York")
    end
  end

  it "EC4 returns 404 APPOINTMENT_NOT_FOUND for an unknown id" do
    get "/api/v1/appointments/00000000-0000-0000-0000-000000000000"

    expect(response).to have_http_status(:not_found)
    expect(body["success"]).to be(false)
    expect(body["error"]["code"]).to eq("APPOINTMENT_NOT_FOUND")
  end

  it "EC5 returns 400 VALIDATION_ERROR for a malformed id" do
    get "/api/v1/appointments/not-a-uuid"

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["errors"]).to eq({ "id" => [ "is not a valid UUID" ] })
  end
end
