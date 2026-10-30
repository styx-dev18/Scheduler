require "rails_helper"

RSpec.describe Availability::FreeBays do
  let(:dealership) { create(:dealership) }
  let(:service_type) { create(:service_type) }
  let(:interval) { Scheduling::TimeInterval.new(starts_at: Time.utc(2030, 1, 7, 9), ends_at: Time.utc(2030, 1, 7, 10)) }
  let!(:bay_a1) { create(:service_bay, dealership:, id: "00000000-0000-4000-8000-0000000000a1") }
  let!(:bay_a2) { create(:service_bay, dealership:, id: "00000000-0000-4000-8000-0000000000a2") }

  subject(:ids) { described_class.new(dealership:, service_type:, interval:).call.pluck(:id) }

  before do
    create(:service_bay, dealership:, active: false)
    create(:service_bay, :lift_bay, dealership:)
  end

  def book(bay, from, to, **attrs)
    create(:appointment, dealership:, service_bay: bay, start_at: Time.utc(2030, 1, 7, *from), end_at: Time.utc(2030, 1, 7, *to), **attrs)
  end

  it "AC3 returns active bays of the required type in id order" do
    expect(ids).to eq([ bay_a1.id, bay_a2.id ])
  end

  {
    "overlap at start" => [ [ 8, 30 ], [ 9, 30 ] ],
    "overlap at end" => [ [ 9, 30 ], [ 10, 30 ] ],
    "contained booking" => [ [ 9, 15 ], [ 9, 45 ] ]
  }.each do |label, (from, to)|
    it "AC3 excludes a bay with #{label}" do
      book(bay_a1, from, to)
      expect(ids).to eq([ bay_a2.id ])
    end
  end

  it "AC3 excludes a bay with a block" do
    create(:bay_block, service_bay: bay_a1, start_at: Time.utc(2030, 1, 7, 9), end_at: Time.utc(2030, 1, 7, 10))
    expect(ids).to eq([ bay_a2.id ])
  end

  it "EC2 ignores cancelled and back-to-back appointments" do
    book(bay_a1, [ 9 ], [ 10 ], status: "cancelled")
    book(bay_a1, [ 8 ], [ 9 ])
    expect(ids).to include(bay_a1.id)
  end
end
