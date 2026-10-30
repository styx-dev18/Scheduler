require "rails_helper"

RSpec.describe "POST /api/v1/appointments confirmation" do
  let(:dealership) { create(:dealership, time_zone: "Europe/London") }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }
  let(:payload) do
    {
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      service_type_id: service_type.id,
      dealership_id: dealership.id,
      start_at: "2030-01-07T09:00:00Z"
    }
  end
  let(:body) { JSON.parse(response.body) }

  before do
    travel_to Time.utc(2030, 1, 1)
    create(:dealership_opening_hour, dealership:)
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  def post_booking(headers = {})
    post "/api/v1/appointments", params: payload, headers:
  end

  it "AC4 returns the full confirmation body and a Location header" do
    post_booking

    expect(response).to have_http_status(:created)
    data = body["data"]
    aggregate_failures do
      expect(data.keys).to match_array(%w[id status customer_id vehicle_id service_type_id dealership_id technician_id
                                          service_bay_id start_at end_at local_start_at local_end_at time_zone customer
                                          vehicle service_type dealership technician service_bay])
      expect(data["status"]).to eq("confirmed")
      expect(data["customer"]).to eq({ "id" => customer.id, "name" => customer.name })
      expect(data["vehicle"]).to eq({ "id" => vehicle.id, "make" => vehicle.make, "model" => vehicle.model,
                                      "year" => vehicle.year, "license_plate" => vehicle.license_plate })
      expect(data["service_type"]).to eq({ "id" => service_type.id, "name" => service_type.name,
                                           "duration_minutes" => service_type.duration_minutes })
      expect(data["dealership"]).to eq({ "id" => dealership.id, "name" => dealership.name })
      expect(data["technician"]).to eq({ "id" => tech.id, "display_name" => tech.name })
      expect(data["service_bay"]).to eq({ "id" => bay.id, "label" => bay.name })
      expect(data["start_at"]).to eq("2030-01-07T09:00:00Z")
      expect(data["end_at"]).to eq("2030-01-07T10:00:00Z")
      expect(data["local_start_at"]).to eq("2030-01-07T09:00:00+00:00")
      expect(data["time_zone"]).to eq("Europe/London")
      expect(response.headers["Location"]).to end_with("/api/v1/appointments/#{data['id']}")
    end

    get URI(response.headers["Location"]).path

    expect(response).to have_http_status(:ok)
    expect(body["data"]["id"]).to eq(Appointment.sole.id)
  end

  it "AC5 keeps the Location header on an idempotent replay" do
    post_booking({ "Idempotency-Key" => "key-ac5" })
    first_id = body["data"]["id"]
    first_location = response.headers["Location"]
    post_booking({ "Idempotency-Key" => "key-ac5" })

    expect(response).to have_http_status(:created)
    expect(body["data"]["id"]).to eq(first_id)
    expect(response.headers["Location"]).to eq(first_location)
    expect(Appointment.count).to eq(1)
  end
end
