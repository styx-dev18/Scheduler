require "rails_helper"

RSpec.describe "GET /api/v1/dealerships/:dealership_id/appointments" do
  let(:dealership) { create(:dealership) }
  let(:unknown_id) { "00000000-0000-0000-0000-000000000000" }
  let(:tech_a) { create(:technician, dealership:) }
  let(:tech_b) { create(:technician, dealership:) }
  let(:bay_a) { create(:service_bay, dealership:) }
  let(:bay_b) { create(:service_bay, dealership:) }

  def body = response.parsed_body
  def ids = body["data"].pluck("id")

  def schedule(id = dealership.id, params = {})
    get "/api/v1/dealerships/#{id}/appointments", params:
  end

  def appt(hour, day: 7, **attrs)
    create(:appointment, dealership:, start_at: Time.utc(2030, 1, day, hour), end_at: Time.utc(2030, 1, day, hour + 1), **attrs)
  end

  describe "AC10 filters" do
    let!(:a1) { appt(11, technician: tech_a, service_bay: bay_a) }
    let!(:a2) { appt(9, technician: tech_b, service_bay: bay_b) }
    let!(:a3) { appt(9, day: 8, technician: tech_a, service_bay: bay_a) }
    let!(:cancelled) { appt(14, technician: tech_b, service_bay: bay_a, status: "cancelled") }

    it "AC10 returns the local day sorted by start_at ascending with nested technician and bay" do
      schedule(dealership.id, date: "2030-01-07")

      expect(response).to have_http_status(:ok)
      expect(ids).to eq([ a2.id, a1.id, cancelled.id ])
      expect(body["data"].first).to include(
        "technician" => { "id" => tech_b.id, "display_name" => tech_b.name },
        "service_bay" => { "id" => bay_b.id, "label" => bay_b.name }
      )
      expect(body["meta"]).to eq("page" => 1, "per_page" => 25, "total_pages" => 1, "total_count" => 3)
    end

    it "AC10 filters by technician" do
      schedule(dealership.id, technician_id: tech_a.id)

      expect(ids).to eq([ a1.id, a3.id ])
    end

    it "AC10 filters by service bay" do
      schedule(dealership.id, service_bay_id: bay_b.id)

      expect(ids).to eq([ a2.id ])
    end

    it "AC10 filters by status" do
      schedule(dealership.id, status: "confirmed", date: "2030-01-07")

      expect(ids).to eq([ a2.id, a1.id ])
    end

    it "AC10 returns every day when no date is given" do
      schedule

      expect(ids).to eq([ a2.id, a1.id, cancelled.id, a3.id ])
    end

    it "AC10 paginates" do
      schedule(dealership.id, per_page: 2, page: 2)

      expect(ids.size).to eq(2)
      expect(body["meta"]).to eq("page" => 2, "per_page" => 2, "total_pages" => 2, "total_count" => 4)
    end
  end

  describe "EC11 near local midnight" do
    let(:dealership) { create(:dealership, time_zone: "America/New_York") }
    let!(:late) { create(:appointment, dealership:, start_at: Time.utc(2030, 1, 8, 4, 30), end_at: Time.utc(2030, 1, 8, 5)) }
    let!(:early) { create(:appointment, dealership:, start_at: Time.utc(2030, 1, 8, 5, 15), end_at: Time.utc(2030, 1, 8, 6)) }

    it "EC11 assigns each appointment to its local day" do
      schedule(dealership.id, date: "2030-01-07")
      first_day = ids
      schedule(dealership.id, date: "2030-01-08")

      expect([ first_day, ids ]).to eq([ [ late.id ], [ early.id ] ])
    end
  end

  describe "EC12 unknown or malformed dealership" do
    it "EC12 returns 404 NOT_FOUND for an unknown dealership" do
      schedule(unknown_id)

      expect(response).to have_http_status(:not_found)
      expect(body.dig("error", "code")).to eq("NOT_FOUND")
    end

    it "EC12 returns 400 VALIDATION_ERROR for a malformed dealership id" do
      schedule("nope")

      expect(response).to have_http_status(:bad_request)
      expect(body.dig("error", "code")).to eq("VALIDATION_ERROR")
      expect(body.dig("error", "errors")).to include("dealership_id")
    end
  end

  it "EC13 returns 400 with errors on date and technician_id" do
    schedule(dealership.id, date: "2030-02-30", technician_id: "x")

    expect(response).to have_http_status(:bad_request)
    expect(body.dig("error", "code")).to eq("VALIDATION_ERROR")
    expect(body.dig("error", "errors").keys).to contain_exactly("date", "technician_id")
  end

  it "EC14 returns an empty page for a technician from another dealership" do
    appt(9)
    other = create(:technician)

    schedule(dealership.id, technician_id: other.id)

    expect(response).to have_http_status(:ok)
    expect(body["data"]).to eq([])
  end
end
