require "rails_helper"

RSpec.describe Availability::Alternatives do
  let(:clock) { double("Clock", now: Time.utc(2030, 1, 1)) }
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:day_slots) { Availability::DaySlots.new(clock:, slot_minutes: 15) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }

  def interval(from, to)
    Scheduling::TimeInterval.new(starts_at: from, ends_at: to)
  end

  def book(from, to)
    create(:appointment, dealership:, service_bay: bay, start_at: from, end_at: to)
  end

  def alternatives(count: 3, target:)
    described_class.new(day_slots:, count:).call(dealership:, service_type:, interval: target)
  end

  before do
    create(:dealership_opening_hour, dealership:)
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  it "orders by proximity, breaks ties by earlier start and excludes the requested start" do
    book(Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10))

    result = alternatives(target: interval(Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10)))

    expect(result).to eq([ "2030-01-07T08:00:00Z", "2030-01-07T10:00:00Z", "2030-01-07T10:15:00Z" ])
  end

  it "EC9 returns an empty list when the day is fully booked" do
    book(Time.utc(2030, 1, 7, 8), Time.utc(2030, 1, 7, 17))

    expect(alternatives(target: interval(Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10)))).to eq([])
  end

  it "EC9 honours a smaller count" do
    book(Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10))

    result = alternatives(count: 1, target: interval(Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10)))

    expect(result).to eq([ "2030-01-07T08:00:00Z" ])
  end

  it "EC10 stays on the same local day at the closing boundary" do
    book(Time.utc(2030, 1, 7, 15), Time.utc(2030, 1, 7, 17))

    result = alternatives(target: interval(Time.utc(2030, 1, 7, 16), Time.utc(2030, 1, 7, 17)))

    expect(result).to eq([ "2030-01-07T14:00:00Z", "2030-01-07T13:45:00Z", "2030-01-07T13:30:00Z" ])
  end
end
