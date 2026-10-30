require "rails_helper"

RSpec.describe "GET /api/v1/appointments" do
  let(:customer) { create(:customer) }
  let(:dealership) { create(:dealership) }
  let(:body) { response.parsed_body }

  def book(day, owner: customer, **attrs)
    create(:appointment, customer: owner, dealership:,
                         start_at: Time.utc(2030, 1, day, 9), end_at: Time.utc(2030, 1, day, 10), **attrs)
  end

  def days
    body["data"].map { |item| Time.iso8601(item["start_at"]).day }
  end

  context "with a customer's appointments" do
    before do
      book(7)
      book(8, status: "cancelled")
      book(9)
    end

    it "AC7 lists ascending by default" do
      get "/api/v1/appointments", params: { customer_id: customer.id }

      expect(response).to have_http_status(:ok)
      expect(days).to eq([ 7, 8, 9 ])
    end

    it "AC7 filters by status" do
      get "/api/v1/appointments", params: { customer_id: customer.id, status: "confirmed" }

      expect(days).to eq([ 7, 9 ])
    end

    it "AC7 filters by from and to" do
      get "/api/v1/appointments", params: { customer_id: customer.id, from: "2030-01-08T00:00:00Z", to: "2030-01-09T00:00:00Z" }

      expect(days).to eq([ 8 ])
    end

    it "AC7 combines status with from and to" do
      get "/api/v1/appointments", params: { customer_id: customer.id, status: "confirmed",
                                            from: "2030-01-08T00:00:00Z", to: "2030-01-09T00:00:00Z" }

      expect(response).to have_http_status(:ok)
      expect(body["data"]).to eq([])
    end

    it "AC7 sorts descending" do
      get "/api/v1/appointments", params: { customer_id: customer.id, sort: "desc" }

      expect(days).to eq([ 9, 8, 7 ])
    end
  end

  it "AC8 returns pagination metadata" do
    3.times { |i| book(7 + i) }

    get "/api/v1/appointments", params: { customer_id: customer.id, per_page: 2, page: 2 }

    expect(response).to have_http_status(:ok)
    expect(body["data"].size).to eq(1)
    expect(body["meta"]).to eq("page" => 2, "per_page" => 2, "total_pages" => 2, "total_count" => 3)
  end

  it "AC9 returns only the requested customer's appointments in the full shape" do
    mine = book(7)
    book(7, owner: create(:customer))

    get "/api/v1/appointments", params: { customer_id: customer.id }

    expect(response).to have_http_status(:ok)
    expect(body["data"].size).to eq(1)
    expect(body["data"].first).to include(
      "id" => mine.id,
      "customer" => { "id" => customer.id, "name" => customer.name },
      "time_zone" => dealership.time_zone,
      "technician" => { "id" => mine.technician_id, "display_name" => mine.technician.name },
      "service_bay" => { "id" => mine.service_bay_id, "label" => mine.service_bay.name }
    )
    expect(body["data"].first.keys).to include("vehicle", "service_type", "dealership", "local_start_at", "local_end_at")
  end

  it "EC6 rejects a missing customer_id" do
    get "/api/v1/appointments"

    expect(response).to have_http_status(:bad_request)
    expect(body["success"]).to be(false)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["errors"]["customer_id"]).to be_present
  end

  it "EC7 rejects invalid filters" do
    get "/api/v1/appointments", params: { customer_id: customer.id, status: "bogus", from: "2030-01-08", sort: "up", per_page: 0 }

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["errors"].keys).to contain_exactly("status", "from", "sort", "per_page")
  end

  it "EC7 rejects to before from" do
    get "/api/v1/appointments", params: { customer_id: customer.id, from: "2030-01-08T00:00:00Z", to: "2030-01-07T00:00:00Z" }

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["errors"]).to have_key("to")
  end

  it "EC8 caps per_page at 100" do
    get "/api/v1/appointments", params: { customer_id: customer.id, per_page: 500 }

    expect(response).to have_http_status(:ok)
    expect(body["meta"]["per_page"]).to eq(100)
  end

  it "EC9 rejects a page past the end" do
    book(7)

    get "/api/v1/appointments", params: { customer_id: customer.id, page: 5 }

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
    expect(body["error"]["detail"]).to eq("Invalid page")
  end

  it "EC10 returns an empty list for a customer without appointments" do
    get "/api/v1/appointments", params: { customer_id: customer.id }

    expect(response).to have_http_status(:ok)
    expect(body["data"]).to eq([])
    expect(body["meta"]["total_count"]).to eq(0)
  end
end
