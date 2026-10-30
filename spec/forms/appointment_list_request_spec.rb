require "rails_helper"

RSpec.describe AppointmentListRequest do
  let(:customer_id) { "00000000-0000-4000-8000-000000000001" }

  def form(**attrs)
    described_class.new({ customer_id: }.merge(attrs))
  end

  it "AC7 is valid with only a customer_id" do
    expect(form).to be_valid
  end

  it "EC6 requires customer_id" do
    request = described_class.new({})

    expect(request).not_to be_valid
    expect(request.errors[:customer_id]).to be_present
  end

  it "EC6 rejects a malformed customer_id" do
    request = form(customer_id: "nope")
    request.valid?

    expect(request.errors[:customer_id]).to eq([ "is not a valid UUID" ])
  end

  it "EC7 reports errors on status, from, sort and per_page" do
    request = form(status: "bogus", from: "2030-01-08", sort: "up", per_page: "0")
    request.valid?

    expect(request.errors.attribute_names).to contain_exactly(:status, :from, :sort, :per_page)
  end

  it "EC7 rejects a non-integer per_page" do
    request = form(per_page: "abc")
    request.valid?

    expect(request.errors[:per_page]).to be_present
  end

  it "EC7 rejects to when it is not after from" do
    request = form(from: "2030-01-08T00:00:00Z", to: "2030-01-07T00:00:00Z")
    request.valid?

    expect(request.errors[:to]).to eq([ "must be after from" ])
  end

  it "EC7 rejects an unparseable instant that has an offset" do
    request = form(to: "2030-13-40T00:00:00Z")
    request.valid?

    expect(request.errors[:to]).to be_present
  end

  it "AC7 normalises filters to UTC with a default direction" do
    filters = form(status: "confirmed", from: "2030-01-08T01:00:00+01:00", to: "2030-01-09T00:00:00Z").filters

    expect(filters).to eq(customer_id:, status: "confirmed", from: Time.utc(2030, 1, 8), to: Time.utc(2030, 1, 9), direction: :asc)
  end

  it "AC7 maps a blank status to nil and honours sort desc" do
    expect(form(status: "", sort: "desc").filters).to include(status: nil, direction: :desc)
  end

  it "AC8 uses the default page size when per_page is blank" do
    expect(form.limit).to eq(Pagy::DEFAULT[:limit])
  end

  it "EC8 caps per_page at 100" do
    expect(form(per_page: "500").limit).to eq(100)
  end

  it "AC8 honours a per_page below the cap" do
    expect(form(per_page: "2").limit).to eq(2)
  end
end
