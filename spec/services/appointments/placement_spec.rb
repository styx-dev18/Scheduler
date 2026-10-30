require "rails_helper"

RSpec.describe Appointments::Placement do
  let(:now) { Time.utc(2030, 1, 1) }
  let(:clock) { class_double(Clock, now:) }
  let(:dealership) { create(:dealership, time_zone: "Europe/London") }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:technician) do
    create(:technician, dealership:).tap do |tech|
      create(:technician_qualification, technician: tech, qualification:)
      create(:technician_shift, technician: tech)
    end
  end
  let(:placement) { described_class.new(clock:, slot_minutes: 15) }
  let(:persist) do
    lambda do |assignment, interval|
      create(:appointment, dealership:, customer:, vehicle:, service_type:, technician_id: assignment.technician_id,
                           service_bay_id: assignment.bay_id, start_at: interval.starts_at, end_at: interval.ends_at)
    end
  end

  before { create(:dealership_opening_hour, dealership:) }

  def place(starts_at, **options, &block)
    placement.call(vehicle:, service_type:, dealership:, starts_at:, **options, &(block || persist))
  end

  def code_of(result)
    result.failure.first
  end

  it "AC14 yields the chosen assignment and interval and returns the persisted record" do
    yielded = nil

    result = place(Time.utc(2030, 1, 7, 9)) do |assignment, interval|
      yielded = [ assignment, interval ]
      persist.call(assignment, interval)
    end

    expect(result).to be_success
    expect(yielded.first).to eq(Scheduling::Assignment.new(bay_id: bay.id, technician_id: technician.id))
    expect([ yielded.last.starts_at, yielded.last.ends_at ]).to eq([ Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10) ])
    expect(result.value!).to be_persisted
  end

  {
    "START_TIME_IN_PAST" => Time.utc(2029, 12, 31, 9),
    "START_TIME_NOT_ON_SLOT_GRID" => Time.utc(2030, 1, 7, 9, 10),
    "OUTSIDE_OPENING_HOURS" => Time.utc(2030, 1, 7, 22),
    "DEALERSHIP_CLOSED" => Time.utc(2030, 1, 8, 9)
  }.each do |code, starts_at|
    it "AC14 fails with #{code} without yielding" do
      yielded = false

      result = place(starts_at) { yielded = true }

      expect(code_of(result)).to eq(code)
      expect(yielded).to be(false)
    end
  end

  it "AC14 fails with VEHICLE_ALREADY_BOOKED when the vehicle has an overlapping appointment" do
    existing = create(:appointment, dealership:, customer:, vehicle:, service_type:, technician:, service_bay: bay)

    result = place(Time.utc(2030, 1, 7, 9, 30))

    expect(code_of(result)).to eq("VEHICLE_ALREADY_BOOKED")
    expect(result.failure.last[:extra]).to eq({ appointment_id: existing.id })
  end

  it "AC14 ignores the excluded appointment for vehicle and resource conflicts" do
    existing = create(:appointment, dealership:, customer:, vehicle:, service_type:, technician:, service_bay: bay)

    result = place(Time.utc(2030, 1, 7, 9, 15), exclude_appointment_id: existing.id) do |assignment, interval|
      existing.update!(start_at: interval.starts_at, end_at: interval.ends_at, technician_id: assignment.technician_id,
                       service_bay_id: assignment.bay_id)
      existing
    end

    expect(result.value!.start_at).to eq(Time.utc(2030, 1, 7, 9, 15))
  end

  it "AC14 reports NO_BAY with alternatives when every bay is taken" do
    other_vehicle = create(:vehicle, customer:)
    other_tech = create(:technician, dealership:)
    create(:appointment, dealership:, customer:, vehicle: other_vehicle, service_type:, technician: other_tech,
                         service_bay: bay)

    result = place(Time.utc(2030, 1, 7, 9))

    expect(code_of(result)).to eq("NO_BAY")
    expect(result.failure.last[:extra]).to include(starts_at: "2030-01-07T09:00:00Z", ends_at: "2030-01-07T10:00:00Z")
    expect(result.failure.last[:extra]).to have_key(:alternatives)
  end

  it "AC14 reports NO_CAPACITY when neither a bay nor a technician is free" do
    other_vehicle = create(:vehicle, customer:)
    create(:appointment, dealership:, customer:, vehicle: other_vehicle, service_type:, technician:, service_bay: bay)

    result = place(Time.utc(2030, 1, 7, 9))

    expect(code_of(result)).to eq("NO_CAPACITY")
  end

  describe "preferred assignment" do
    let!(:other_bay) { create(:service_bay, dealership:) }
    let(:strategy) { instance_double(Scheduling::AssignmentStrategies::LeastLoaded) }
    let(:placement) { described_class.new(clock:, strategy:, slot_minutes: 15) }

    before do
      allow(strategy).to receive(:choose)
        .and_return(Scheduling::Assignment.new(bay_id: other_bay.id, technician_id: technician.id))
    end

    it "uses the preferred assignment when both resources are free" do
      preferred = Scheduling::Assignment.new(bay_id: bay.id, technician_id: technician.id)

      result = place(Time.utc(2030, 1, 7, 9), preferred:)

      expect(result.value!.service_bay_id).to eq(bay.id)
      expect(strategy).not_to have_received(:choose)
    end

    it "falls back to the strategy when the preferred bay is not a candidate" do
      busy_vehicle = create(:vehicle, customer:)
      busy_tech = create(:technician, dealership:)
      create(:appointment, dealership:, customer:, vehicle: busy_vehicle, service_type:, technician: busy_tech,
                           service_bay: bay)
      preferred = Scheduling::Assignment.new(bay_id: bay.id, technician_id: technician.id)

      result = place(Time.utc(2030, 1, 7, 9), preferred:)

      expect(result.value!.service_bay_id).to eq(other_bay.id)
      expect(strategy).to have_received(:choose)
    end
  end

  it "AC14 retries without the bay that raised an exclusion violation" do
    free_bay = create(:service_bay, dealership:)
    busy_vehicle = create(:vehicle, customer:)
    busy_tech = create(:technician, dealership:)
    create(:appointment, dealership:, customer:, vehicle: busy_vehicle, service_type:, technician: busy_tech,
                         service_bay: bay)
    candidates = Availability::Finder::Candidates.new(bay_ids: [ bay.id, free_bay.id ], technician_ids: [ technician.id ],
                                                      technician_loads: {})
    finder = instance_double(Availability::Finder, call: candidates)
    strategy = instance_double(Scheduling::AssignmentStrategies::LeastLoaded)
    allow(strategy).to receive(:choose) do |bays:, technicians:, **|
      Scheduling::Assignment.new(bay_id: bays.first, technician_id: technicians.first)
    end
    retrying = described_class.new(clock:, availability: finder, strategy:, slot_minutes: 15)

    result = retrying.call(vehicle:, service_type:, dealership:, starts_at: Time.utc(2030, 1, 7, 9), &persist)

    expect(result.value!.service_bay_id).to eq(free_bay.id)
    expect(strategy).to have_received(:choose).twice
  end

  it "AC14 reports NO_CAPACITY after the retries run out of resources" do
    busy_vehicle = create(:vehicle, customer:)
    busy_tech = create(:technician, dealership:)
    create(:appointment, dealership:, customer:, vehicle: busy_vehicle, service_type:, technician: busy_tech,
                         service_bay: bay)
    candidates = Availability::Finder::Candidates.new(bay_ids: [ bay.id ], technician_ids: [ technician.id ],
                                                      technician_loads: {})
    finder = instance_double(Availability::Finder, call: candidates)
    retrying = described_class.new(clock:, availability: finder, slot_minutes: 15)

    result = retrying.call(vehicle:, service_type:, dealership:, starts_at: Time.utc(2030, 1, 7, 9), &persist)

    expect(code_of(result)).to eq("NO_CAPACITY")
  end
end
