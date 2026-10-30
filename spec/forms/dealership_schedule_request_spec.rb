require "rails_helper"

RSpec.describe DealershipScheduleRequest do
  let(:uuid) { "00000000-0000-4000-8000-000000000001" }

  def form(**attrs) = described_class.new({ dealership_id: uuid }.merge(attrs))

  it "AC10 is valid with only a dealership id" do
    expect(form).to be_valid
  end

  it "EC13 rejects an impossible date and a malformed technician id" do
    request = form(date: "2030-02-30", technician_id: "x")

    request.valid?

    expect(request.errors.attribute_names).to contain_exactly(:date, :technician_id)
  end

  it "EC12 rejects a malformed dealership id" do
    request = form(dealership_id: "nope")

    request.valid?

    expect(request.errors[:dealership_id]).to eq([ "is not a valid UUID" ])
  end

  it "EC12 rejects a missing dealership id" do
    request = described_class.new

    request.valid?

    expect(request.errors).to include(:dealership_id)
  end

  it "AC10 omits the day bounds when no date is given" do
    filters = form.filters("Europe/London")

    expect([ filters[:from], filters[:to], filters[:direction] ]).to eq([ nil, nil, :asc ])
  end

  it "EC11 builds local-midnight bounds for the dealership zone" do
    filters = form(date: "2030-01-07").filters("America/New_York")

    expect([ filters[:from].utc, filters[:to].utc ]).to eq([ Time.utc(2030, 1, 7, 5), Time.utc(2030, 1, 8, 5) ])
  end

  it "EC11 builds a 23-hour day across a spring-forward change" do
    filters = form(date: "2030-03-10").filters("America/New_York")

    expect(filters[:to] - filters[:from]).to eq(23 * 3600)
  end

  it "EC14 passes the technician and bay ids through and blanks to nil" do
    filters = form(technician_id: uuid, service_bay_id: "", status: "").filters("Europe/London")

    expect([ filters[:technician_id], filters[:service_bay_id], filters[:status] ]).to eq([ uuid, nil, nil ])
  end

  it "AC10 rejects an unknown status and a zero per_page" do
    request = form(status: "bogus", per_page: "0")

    request.valid?

    expect(request.errors.attribute_names).to contain_exactly(:status, :per_page)
  end

  it "AC10 clamps the limit to 100, defaults to 25 and honours a smaller value" do
    expect([ form(per_page: "500").limit, form.limit, form(per_page: "7").limit ]).to eq([ 100, 25, 7 ])
  end
end
