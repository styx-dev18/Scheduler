require "rails_helper"

RSpec.describe "POST /api/v1/appointments" do
  let(:dealership) { create(:dealership) }
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
  let(:unknown_id) { "00000000-0000-4000-8000-000000000000" }

  before do
    travel_to Time.utc(2030, 1, 1)
    create(:dealership_opening_hour, dealership:)
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  def post_booking(params = payload, headers = {})
    post "/api/v1/appointments", params:, headers:
  end

  it "AC10 books a slot" do
    expect { post_booking }.to change(Appointment, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(body["data"]).to include("status" => "confirmed", "service_bay_id" => bay.id, "technician_id" => tech.id,
                                    "start_at" => "2030-01-07T09:00:00Z", "end_at" => "2030-01-07T10:00:00Z")
  end

  it "AC11 normalises an offset start" do
    post_booking(payload.merge(start_at: "2030-01-07T10:00:00+01:00"))

    expect(response).to have_http_status(:created)
    expect(body["data"]["start_at"]).to eq("2030-01-07T09:00:00Z")
  end

  it "EC6 rejects a missing vehicle_id" do
    post_booking(payload.except(:vehicle_id))

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["errors"]["vehicle_id"]).to include("can't be blank")
  end

  it "EC6 rejects a start without an offset" do
    post_booking(payload.merge(start_at: "2030-01-07T09:00:00"))

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["errors"]["start_at"]).to eq([ "must be an ISO-8601 timestamp with a UTC offset" ])
  end

  it "EC7 returns 404 for an unknown customer" do
    post_booking(payload.merge(customer_id: unknown_id))

    expect(response).to have_http_status(:not_found)
    expect(body["error"]["code"]).to eq("NOT_FOUND")
    expect(body["error"]["detail"]).to eq("Customer not found")
  end

  it "EC8 rejects a start in the past" do
    travel_to Time.utc(2030, 1, 7, 9)
    post_booking

    expect(response).to have_http_status(:unprocessable_content)
    expect(body["error"]["code"]).to eq("START_TIME_IN_PAST")
  end

  it "EC9 rejects an off-grid start" do
    post_booking(payload.merge(start_at: "2030-01-07T09:10:00Z"))

    expect(response).to have_http_status(:unprocessable_content)
    expect(body["error"]["code"]).to eq("START_TIME_NOT_ON_SLOT_GRID")
  end

  it "EC10 rejects a vehicle owned by someone else without revealing the owner" do
    owner = create(:customer)
    other = create(:vehicle, customer: owner)

    expect { post_booking(payload.merge(vehicle_id: other.id)) }.not_to change(Appointment, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(body["error"]["code"]).to eq("VEHICLE_OWNERSHIP_MISMATCH")
    expect(response.body).not_to include(owner.id)
  end

  it "AC14 rejects a start outside opening hours" do
    post_booking(payload.merge(start_at: "2030-01-07T16:15:00Z"))

    expect(response).to have_http_status(:unprocessable_content)
    expect(body["error"]["code"]).to eq("OUTSIDE_OPENING_HOURS")
  end

  it "EC11 rejects a holiday" do
    create(:dealership_holiday, dealership:, holiday_on: Date.new(2030, 1, 7))
    post_booking

    expect(response).to have_http_status(:unprocessable_content)
    expect(body["error"]["code"]).to eq("DEALERSHIP_CLOSED")
  end

  it "EC12 rejects an overlapping booking of the same vehicle" do
    existing = create(:appointment, dealership:, customer:, vehicle:, service_type:)

    expect { post_booking(payload.merge(start_at: "2030-01-07T09:30:00Z")) }.not_to change(Appointment, :count)

    expect(response).to have_http_status(:conflict)
    expect(body["error"]["code"]).to eq("VEHICLE_ALREADY_BOOKED")
    expect(body["error"]["appointment_id"]).to eq(existing.id)
  end

  it "AC16 allows back-to-back bookings" do
    create(:appointment, dealership:, customer:, vehicle:, service_type:)
    post_booking(payload.merge(start_at: "2030-01-07T10:00:00Z"))

    expect(response).to have_http_status(:created)
  end

  it "EC5 reports no capacity when bay and technician are busy" do
    other = create(:vehicle)
    create(:appointment, dealership:, customer: other.customer, vehicle: other, technician: tech, service_bay: bay, service_type:)

    expect { post_booking }.not_to change(Appointment, :count)

    expect(response).to have_http_status(:conflict)
    expect(body["error"]["code"]).to eq("NO_CAPACITY")
    expect(body["error"]).to include("starts_at", "ends_at")
    expect(body["error"]["alternatives"]).to eq([ "2030-01-07T08:00:00Z", "2030-01-07T10:00:00Z", "2030-01-07T10:15:00Z" ])
  end

  it "AC17 replays a stored response for the same key" do
    post_booking(payload, { "Idempotency-Key" => "idem-ac17" })
    first = JSON.parse(response.body)
    post_booking(payload, { "Idempotency-Key" => "idem-ac17" })

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to eq(first)
    expect(Appointment.count).to eq(1)
  end

  it "EC13 rejects a key reused with another payload" do
    post_booking(payload, { "Idempotency-Key" => "idem-ec13" })

    expect { post_booking(payload.merge(start_at: "2030-01-07T11:00:00Z"), { "Idempotency-Key" => "idem-ec13" }) }
      .not_to change(Appointment, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(body["error"]["code"]).to eq("IDEMPOTENCY_KEY_REUSED")
  end

  it "EC15 rejects an over-long key" do
    post_booking(payload, { "Idempotency-Key" => "k" * 256 })

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["errors"]).to have_key("Idempotency-Key")
  end
end
