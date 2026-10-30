require "rails_helper"

RSpec.describe Availability::Finder do
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:interval) { Scheduling::TimeInterval.new(starts_at: Time.utc(2030, 1, 7, 9), ends_at: Time.utc(2030, 1, 7, 10)) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }

  before do
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  def book(status: "confirmed", day: 7, hour:)
    create(:appointment, dealership:, technician: tech, status:, start_at: Time.utc(2030, 1, day, hour), end_at: Time.utc(2030, 1, day, hour + 1))
  end

  it "AC6 reports ids and local-day load of active appointments" do
    book(hour: 12)
    book(hour: 14)
    book(hour: 15, status: "cancelled")
    book(day: 6, hour: 12)

    result = described_class.new.call(dealership:, service_type:, interval:)

    expect(result.bay_ids).to eq(Availability::FreeBays.new(dealership:, service_type:, interval:).call.pluck(:id))
    expect(result.technician_ids).to eq([ tech.id ])
    expect(result.technician_loads[tech.id]).to eq(2)
  end

  it "returns empty loads when nobody is free" do
    result = described_class.new.call(dealership:, service_type: create(:service_type, required_bay_type: "lift"), interval:)
    expect(result.bay_ids).to eq([])
    expect(result.technician_loads).to eq({})
  end
end
