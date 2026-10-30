require "rails_helper"

RSpec.describe "GET /api/v1/availability" do
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }
  def body = JSON.parse(response.body)
  let(:unknown_id) { "00000000-0000-4000-8000-000000000000" }
  let(:query) { { dealership_id: dealership.id, service_type_id: service_type.id, date: "2030-01-07" } }

  before do
    travel_to Time.utc(2030, 1, 1)
    create(:dealership_opening_hour, dealership:)
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  def get_availability(params = query)
    get "/api/v1/availability", params:
  end

  def book
    post "/api/v1/appointments", params: {
      customer_id: customer.id, vehicle_id: vehicle.id, service_type_id: service_type.id,
      dealership_id: dealership.id, start_at: "2030-01-07T09:00:00Z"
    }
  end

  it "AC10 lists the day's slots and reflects a booking" do
    get_availability

    expect(response).to have_http_status(:ok)
    expect(body["data"]).to include("dealership_id" => dealership.id, "service_type_id" => service_type.id,
                                    "date" => "2030-01-07", "time_zone" => "Europe/London")
    expect(body["data"]["slots"].size).to eq(33)
    expect(body["data"]["slots"].first).to eq("start_at" => "2030-01-07T08:00:00Z",
                                              "local_start_at" => "2030-01-07T08:00:00+00:00")

    book
    get_availability

    expect(body["data"]["slots"].size).to eq(26)
  end

  context "with a cache store" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "AC11 serves a cached day for 30 seconds" do
      get_availability
      book
      get_availability
      expect(body["data"]["slots"].size).to eq(33)

      travel 31.seconds
      get_availability
      expect(body["data"]["slots"].size).to eq(26)
    end
  end

  it "EC6 rejects a missing date" do
    get_availability(query.except(:date))

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["errors"]["date"]).to eq([ "can't be blank" ])
  end

  it "EC6 rejects malformed dates" do
    [ "2030-02-30", "07/01/2030" ].each do |date|
      get_availability(query.merge(date:))

      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["errors"]["date"]).to eq([ "must be a date in YYYY-MM-DD format" ])
    end
  end

  it "EC6 rejects a malformed dealership_id" do
    get_availability(query.merge(dealership_id: "abc"))

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["errors"]["dealership_id"]).to eq([ "is not a valid UUID" ])
  end

  it "EC7 returns 404 for unknown ids" do
    [ { dealership_id: unknown_id }, { service_type_id: unknown_id } ].each do |override|
      get_availability(query.merge(override))

      expect(response).to have_http_status(:not_found)
      expect(body["error"]["code"]).to eq("NOT_FOUND")
    end
  end

  it "EC8 returns no slots on a holiday and on a closed day" do
    create(:dealership_holiday, dealership:, holiday_on: Date.new(2030, 1, 7))

    [ "2030-01-07", "2030-01-06" ].each do |date|
      get_availability(query.merge(date:))

      expect(response).to have_http_status(:ok)
      expect(body["data"]["slots"]).to eq([])
    end
  end
end
