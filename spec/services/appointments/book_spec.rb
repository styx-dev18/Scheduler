require "rails_helper"

RSpec.describe Appointments::Book do
  let(:now) { Time.utc(2030, 1, 1) }
  let(:clock) { class_double(Clock, now:) }
  let(:candidates_class) { Availability::Finder::Candidates }
  let(:finder) { instance_double(Availability::Finder) }
  let(:strategy) { instance_double(Scheduling::AssignmentStrategies::LeastLoaded) }
  let(:dealership) { create(:dealership) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let(:service_type) { create(:service_type) }
  let(:bay) { create(:service_bay, dealership:) }
  let(:technician) { create(:technician, dealership:) }
  let(:start_at) { "2030-01-07T09:00:00Z" }
  let(:params) do
    { customer_id: customer.id, vehicle_id: vehicle.id, service_type_id: service_type.id, dealership_id: dealership.id, start_at: }
  end
  let(:candidates) { candidates_class.new(bay_ids: [ bay.id ], technician_ids: [ technician.id ], technician_loads: {}) }
  let(:service) { described_class.new(clock:, availability: finder, strategy:, slot_minutes: 15) }

  before do
    create(:dealership_opening_hour, dealership:)
    allow(finder).to receive(:call).and_return(candidates)
    allow(strategy).to receive(:choose).and_return(Scheduling::Assignment.new(bay_id: bay.id, technician_id: technician.id))
  end

  def code_of(result)
    result.failure.first
  end

  it "AC13 returns Success with a persisted appointment" do
    result = service.call(params)

    expect(result).to be_success
    appointment = result.value!
    expect(appointment).to be_persisted
    expect(appointment.start_at).to eq(Time.utc(2030, 1, 7, 9))
    expect(appointment.end_at).to eq(Time.utc(2030, 1, 7, 10))
    expect(appointment.service_bay_id).to eq(bay.id)
    expect(appointment.technician_id).to eq(technician.id)
  end

  it "AC12 persists whatever the injected strategy chooses" do
    other_bay = create(:service_bay, dealership:)
    allow(strategy).to receive(:choose).and_return(Scheduling::Assignment.new(bay_id: other_bay.id, technician_id: technician.id))

    expect(service.call(params).value!.service_bay_id).to eq(other_bay.id)
  end

  it "AC11 normalises offsets to UTC" do
    result = service.call(params.merge(start_at: "2030-01-07T10:00:00+01:00"))

    expect(result.value!.start_at).to eq(Time.utc(2030, 1, 7, 9))
  end

  it "EC6 fails with VALIDATION_ERROR and field errors" do
    result = service.call(params.merge(vehicle_id: nil, customer_id: "not-a-uuid"))

    expect(code_of(result)).to eq("VALIDATION_ERROR")
    errors = result.failure.last[:errors]
    expect(errors[:vehicle_id]).to eq([ "can't be blank" ])
    expect(errors[:customer_id]).to eq([ "is not a valid UUID" ])
  end

  it "EC6 rejects a start_at without an offset" do
    result = service.call(params.merge(start_at: "2030-01-07T09:00:00"))

    expect(result.failure.last[:errors][:start_at]).to eq([ "must be an ISO-8601 timestamp with a UTC offset" ])
  end

  it "EC6 rejects an unparsable start_at" do
    result = service.call(params.merge(start_at: "2030-13-45T99:00:00Z"))

    expect(code_of(result)).to eq("VALIDATION_ERROR")
  end

  it "EC8 fails when start is now or earlier" do
    expect(code_of(service.call(params.merge(start_at: "2030-01-01T00:00:00Z")))).to eq("START_TIME_IN_PAST")
    expect(code_of(service.call(params.merge(start_at: "2029-12-31T23:45:00Z")))).to eq("START_TIME_IN_PAST")
  end

  it "EC9 fails when start is off the slot grid" do
    expect(code_of(service.call(params.merge(start_at: "2030-01-07T09:10:00Z")))).to eq("START_TIME_NOT_ON_SLOT_GRID")
    expect(code_of(service.call(params.merge(start_at: "2030-01-07T09:00:30Z")))).to eq("START_TIME_NOT_ON_SLOT_GRID")
  end

  it "EC7 fails with NOT_FOUND naming the missing resource" do
    missing = "00000000-0000-4000-8000-000000000000"
    {
      customer_id: "Customer not found",
      vehicle_id: "Vehicle not found",
      service_type_id: "Service type not found",
      dealership_id: "Dealership not found"
    }.each do |field, detail|
      result = service.call(params.merge(field => missing))

      expect(code_of(result)).to eq("NOT_FOUND")
      expect(result.failure.last[:detail]).to eq(detail)
      expect(result.failure.last[:errors]).to eq(field.to_s => [ "not found" ])
    end
  end

  it "EC10 fails when the vehicle belongs to someone else without revealing the owner" do
    owner = create(:customer)
    foreign = create(:vehicle, customer: owner)

    result = service.call(params.merge(vehicle_id: foreign.id))

    expect(code_of(result)).to eq("VEHICLE_OWNERSHIP_MISMATCH")
    expect(result.failure.last.to_s).not_to include(owner.id)
    expect(Appointment.count).to eq(0)
  end

  it "AC14 fails outside opening hours" do
    expect(code_of(service.call(params.merge(start_at: "2030-01-07T16:15:00Z")))).to eq("OUTSIDE_OPENING_HOURS")
  end

  it "EC11 fails with DEALERSHIP_CLOSED on a holiday and a closed weekday" do
    create(:dealership_holiday, dealership:, holiday_on: Date.new(2030, 1, 7))

    expect(code_of(service.call(params))).to eq("DEALERSHIP_CLOSED")
    expect(code_of(service.call(params.merge(start_at: "2030-01-06T09:00:00Z")))).to eq("DEALERSHIP_CLOSED")
  end

  it "EC12 fails with VEHICLE_ALREADY_BOOKED and the blocking appointment id" do
    existing = create(:appointment, customer:, vehicle:)

    result = service.call(params.merge(start_at: "2030-01-07T09:30:00Z"))

    expect(code_of(result)).to eq("VEHICLE_ALREADY_BOOKED")
    expect(result.failure.last[:extra]).to eq(appointment_id: existing.id)
  end

  it "AC16 allows back-to-back and cancelled appointments for the same vehicle" do
    create(:appointment, customer:, vehicle:)
    create(:appointment, :cancelled, customer:, vehicle:, start_at: Time.utc(2030, 1, 7, 11), end_at: Time.utc(2030, 1, 7, 12))

    expect(service.call(params.merge(start_at: "2030-01-07T10:00:00Z"))).to be_success
    expect(service.call(params.merge(start_at: "2030-01-07T11:00:00Z"))).to be_success
  end

  it "EC5 maps empty candidates to NO_BAY, NO_TECHNICIAN and NO_CAPACITY with the interval and alternatives" do
    alternatives = instance_double(Availability::Alternatives, call: [ "2030-01-07T08:00:00Z" ])
    service = described_class.new(clock:, availability: finder, strategy:, alternatives:, slot_minutes: 15)
    {
      "NO_BAY" => candidates_class.new(bay_ids: [], technician_ids: [ technician.id ], technician_loads: {}),
      "NO_TECHNICIAN" => candidates_class.new(bay_ids: [ bay.id ], technician_ids: [], technician_loads: {}),
      "NO_CAPACITY" => candidates_class.new(bay_ids: [], technician_ids: [], technician_loads: {})
    }.each do |code, empty|
      allow(finder).to receive(:call).and_return(empty)

      result = service.call(params)

      expect(code_of(result)).to eq(code)
      expect(result.failure.last[:extra]).to eq(
        starts_at: "2030-01-07T09:00:00Z", ends_at: "2030-01-07T10:00:00Z", alternatives: [ "2030-01-07T08:00:00Z" ]
      )
    end
    expect(Appointment.count).to eq(0)
  end

  it "returns NO_CAPACITY when the strategy chooses nothing" do
    allow(strategy).to receive(:choose).and_return(nil)

    expect(code_of(service.call(params))).to eq("NO_CAPACITY")
  end

  it "passes candidates and loads to the strategy" do
    loaded = candidates_class.new(bay_ids: [ bay.id ], technician_ids: [ technician.id ], technician_loads: { technician.id => 2 })
    allow(finder).to receive(:call).and_return(loaded)

    service.call(params)

    expect(strategy).to have_received(:choose).with(
      bays: [ bay.id ], technicians: [ technician.id ], interval: kind_of(Scheduling::TimeInterval), loads: { technician.id => 2 }
    )
  end

  context "with the real finder and strategy" do
    let(:qualification) { create(:qualification) }
    let(:service_type) { create(:service_type, required_qualification: qualification) }
    let(:real_service) { described_class.new(clock:, slot_minutes: 15) }
    let(:other_customer) { create(:customer) }
    let(:bay_a1) { create(:service_bay, dealership:, id: "00000000-0000-4000-8000-0000000000a1") }
    let(:bay_a2) { create(:service_bay, dealership:, id: "00000000-0000-4000-8000-0000000000a2") }
    let(:tech_a1) { create(:technician, dealership:) }
    let(:bay) { bay_a1 }
    let(:technician) { tech_a1 }
    let(:slot) { { start_at: Time.utc(2030, 1, 7, 9), end_at: Time.utc(2030, 1, 7, 10) } }
    let(:window) { { starts_at: "2030-01-07T09:00:00Z", ends_at: "2030-01-07T10:00:00Z" } }

    before do
      create(:technician_qualification, technician: tech_a1, qualification:)
      create(:technician_shift, technician: tech_a1)
      bay_a1
      bay_a2
    end

    def occupy_bays
      [ bay_a1, bay_a2 ].each do |occupied_bay|
        create(:appointment, dealership:, customer: other_customer, service_bay: occupied_bay, **slot)
      end
    end

    def take_time_off
      create(:technician_time_off, technician: tech_a1, start_at: slot[:start_at], end_at: slot[:end_at])
    end

    {
      "NO_BAY" => :occupy_bays,
      "NO_TECHNICIAN" => :take_time_off
    }.each do |code, setup|
      it "AC5 returns #{code} from real data without leaking other customers" do
        send(setup)

        result = nil
        expect { result = real_service.call(params) }.not_to change(Appointment, :count)

        expect(code_of(result)).to eq(code)
        expect(result.failure.last[:extra]).to include(window)
        leaked = [ other_customer.id, *other_customer.vehicles.ids, *Appointment.where(customer: other_customer).ids ]
        expect(leaked.none? { |id| result.failure.to_s.include?(id) }).to be(true)
      end
    end

    it "AC5 returns NO_CAPACITY from real data without leaking other customers" do
      occupy_bays
      take_time_off

      result = nil
      expect { result = real_service.call(params) }.not_to change(Appointment, :count)

      expect(code_of(result)).to eq("NO_CAPACITY")
      expect(result.failure.last[:extra]).to include(window)
      leaked = [ other_customer.id, *Appointment.where(customer: other_customer).ids ]
      expect(leaked.none? { |id| result.failure.to_s.include?(id) }).to be(true)
    end

    context "with suggested alternatives" do
      let(:alternatives) do
        Availability::Alternatives.new(day_slots: Availability::DaySlots.new(clock:, slot_minutes: 15), count: 3)
      end
      let(:alternative_service) { described_class.new(clock:, alternatives:, slot_minutes: 15) }

      it "AC13 suggests the nearest starts and each one books" do
        occupy_bays

        result = alternative_service.call(params)

        expected = [ "2030-01-07T08:00:00Z", "2030-01-07T10:00:00Z", "2030-01-07T10:15:00Z" ]
        expect(code_of(result)).to eq("NO_BAY")
        expect(result.failure.last[:extra][:alternatives]).to eq(expected)
        expected.each do |alternative|
          ApplicationRecord.transaction(requires_new: true) do
            expect(alternative_service.call(params.merge(start_at: alternative))).to be_success
            raise ActiveRecord::Rollback
          end
        end
      end

      it "EC9 returns an empty list when nothing is left that day" do
        [ bay_a1, bay_a2 ].each do |occupied_bay|
          create(:appointment, dealership:, customer: other_customer, service_bay: occupied_bay,
                               start_at: Time.utc(2030, 1, 7, 8), end_at: Time.utc(2030, 1, 7, 17))
        end

        result = alternative_service.call(params)

        expect(code_of(result)).to eq("NO_BAY")
        expect(result.failure.last[:extra][:alternatives]).to eq([])
      end
    end

    context "when a concurrent booking holds the first candidate bay" do
      let(:tech_ac6) { create(:technician, dealership:) }
      let(:retry_finder) { instance_double(Availability::Finder) }
      let(:retry_service) do
        described_class.new(clock:, availability: retry_finder, strategy: Scheduling::AssignmentStrategies::LeastLoaded.new, slot_minutes: 15)
      end

      before do
        create(:appointment, dealership:, customer: other_customer, service_bay: bay_a1, technician: tech_ac6, **slot)
      end

      it "AC6 retries with the next candidate bay" do
        allow(retry_finder).to receive(:call).and_return(
          candidates_class.new(bay_ids: [ bay_a1.id, bay_a2.id ], technician_ids: [ tech_a1.id ], technician_loads: {})
        )

        result = nil
        expect { result = retry_service.call(params) }.to change(Appointment, :count).by(1)

        expect(result).to be_success
        expect(result.value!.service_bay_id).to eq(bay_a2.id)
      end

      it "EC2 fails with NO_CAPACITY when retries run out" do
        allow(retry_finder).to receive(:call).and_return(
          candidates_class.new(bay_ids: [ bay_a1.id ], technician_ids: [ tech_a1.id ], technician_loads: {})
        )

        result = nil
        expect { result = retry_service.call(params) }.not_to change(Appointment, :count)

        expect(code_of(result)).to eq("NO_CAPACITY")
      end
    end
  end
end
