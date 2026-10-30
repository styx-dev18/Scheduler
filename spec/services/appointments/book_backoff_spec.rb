require "rails_helper"

RSpec.describe Appointments::Book, "backoff" do
  let(:dealership) { create(:dealership) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let(:service_type) { create(:service_type) }
  let!(:technician) { create(:technician, dealership:) }
  let(:bays) { create_list(:service_bay, 6, dealership:) }
  let(:params) do
    {
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      service_type_id: service_type.id,
      dealership_id: dealership.id,
      start_at: "2030-01-07T09:00:00Z"
    }
  end
  let(:finder) { instance_double(Availability::Finder) }
  let(:strategy) { instance_double(Scheduling::AssignmentStrategies::LeastLoaded) }
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:jitter) { -> { 1.0 } }
  let(:service) { described_class.new(availability: finder, strategy:, jitter:, sleeper:) }

  before do
    create(:dealership_opening_hour, dealership:)
    allow(finder).to receive(:call).and_return(
      Availability::Finder::Candidates.new(bay_ids: bays.map(&:id), technician_ids: [ technician.id ], technician_loads: {})
    )
    allow(strategy).to receive(:choose) do |bays:, technicians:, **|
      Scheduling::Assignment.new(bay_id: bays.first, technician_id: technicians.first)
    end
  end

  def occupy(bay_list)
    bay_list.each { |bay| create(:appointment, dealership:, service_bay: bay) }
  end

  it "AC6 does not sleep when the first assignment succeeds" do
    result = service.call(params)

    expect(result).to be_success
    expect(sleeps).to be_empty
  end

  it "AC6 sleeps with a growing delay between retries and stops at the existing max attempts" do
    occupy(bays.first(3))

    result = service.call(params)

    expect(result.failure.first).to eq("NO_CAPACITY")
    expect(sleeps).to eq([ 0.02, 0.04 ])
    expect(sleeps.size).to be <= Appointments::Placement::MAX_ASSIGNMENT_ATTEMPTS - 1
  end

  it "AC6 sleeps once and succeeds when the second attempt wins" do
    occupy(bays.first(1))

    result = service.call(params)

    expect(result).to be_success
    expect(result.value!.service_bay_id).to eq(bays.second.id)
    expect(sleeps).to eq([ 0.02 ])
  end

  it "AC6 scales each delay by the injected jitter" do
    occupy(bays.first(3))
    half = described_class.new(availability: finder, strategy:, jitter: -> { 0.5 }, sleeper:)

    half.call(params)

    expect(sleeps).to eq([ 0.01, 0.02 ])
  end

  it "AC6 caps the delay and never exceeds the cap" do
    stub_const("Appointments::Placement::MAX_ASSIGNMENT_ATTEMPTS", 6)
    occupy(bays)

    service.call(params)

    expect(sleeps.size).to eq(5)
    expect(sleeps).to eq(sleeps.sort)
    expect(sleeps.first).to be < sleeps.last
    expect(sleeps.max).to eq(described_class::BACKOFF_CAP_SECONDS)
    expect(sleeps).to all(be <= described_class::BACKOFF_CAP_SECONDS)
  end
end
