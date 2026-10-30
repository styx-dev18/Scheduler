require "rails_helper"

RSpec.describe Appointments::Reschedule do
  let(:now) { Time.utc(2030, 1, 1) }
  let(:clock) { class_double(Clock, now:) }
  let(:dealership) { create(:dealership, time_zone: "Europe/London") }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:technician) { add_technician }
  let!(:appointment) do
    create(:appointment, dealership:, customer:, vehicle:, service_type:, technician:, service_bay: bay)
  end
  let(:service) { described_class.new(clock:) }

  before { create(:dealership_opening_hour, dealership:) }

  def add_technician
    create(:technician, dealership:).tap do |tech|
      create(:technician_qualification, technician: tech, qualification:)
      create(:technician_shift, technician: tech)
    end
  end

  def reschedule(target = appointment, **params)
    service.call(appointment_id: target.id, params:)
  end

  def capture_events
    events = []
    handler = ->(name, _start, _finish, _id, payload) { events << [ name, payload ] }
    ActiveSupport::Notifications.subscribed(handler, /\Aappointment\./) { yield }
    events
  end

  def code_of(result)
    result.failure.first
  end

  def snapshot(record)
    record.reload.slice(:start_at, :end_at, :service_bay_id, :technician_id, :status, :lock_version)
  end

  it "AC4 updates the same row, writes the reschedule row and publishes the event" do
    Current.request_id = "req-ac4"
    original_id = appointment.id

    events = capture_events { @result = reschedule(new_start_at: "2030-01-07T13:00:00Z", lock_version: 0) }

    expect(@result).to be_success
    appointment.reload
    aggregate_failures do
      expect(appointment.id).to eq(original_id)
      expect([ appointment.start_at, appointment.end_at, appointment.lock_version ])
        .to eq([ Time.utc(2030, 1, 7, 13), Time.utc(2030, 1, 7, 14), 1 ])
      row = appointment.reschedules.sole
      expect([ row.prev_start_at, row.prev_end_at, row.new_start_at, row.new_end_at, row.actor, row.request_id ])
        .to eq([ Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10), Time.utc(2030, 1, 7, 13), Time.utc(2030, 1, 7, 14),
                 "customer", "req-ac4" ])
      name, payload = events.sole
      expect(name).to eq("appointment.rescheduled")
      expect(payload).to include(appointment_id: original_id, previous_start_at: Time.utc(2030, 1, 7, 9),
                                 previous_end_at: Time.utc(2030, 1, 7, 10), request_id: "req-ac4", occurred_at: now,
                                 technician_id: technician.id, service_bay_id: bay.id)
    end
  ensure
    Current.reset
  end

  it "AC4 frees the old interval for another vehicle in the same bay" do
    reschedule(new_start_at: "2030-01-07T13:00:00Z")

    other = build(:appointment, dealership:, technician:, service_bay: bay)

    expect(other.save).to be(true)
  end

  it "AC5 shifts by 15 minutes over its own old interval keeping bay and technician" do
    expect { reschedule(new_start_at: "2030-01-07T09:15:00Z") }.not_to change(Appointment, :count)

    appointment.reload
    expect([ appointment.start_at, appointment.end_at, appointment.service_bay_id, appointment.technician_id ])
      .to eq([ Time.utc(2030, 1, 7, 9, 15), Time.utc(2030, 1, 7, 10, 15), bay.id, technician.id ])
  end

  it "AC6 leaves the original intact when no bay is free" do
    other_tech = add_technician
    create(:appointment, dealership:, service_type:, technician: other_tech, service_bay: bay,
                         start_at: Time.utc(2030, 1, 7, 11), end_at: Time.utc(2030, 1, 7, 12))
    before_state = snapshot(appointment)

    events = capture_events { @result = reschedule(new_start_at: "2030-01-07T11:00:00Z") }

    expect(code_of(@result)).to eq("NO_BAY")
    expect(@result.failure.last[:extra]).to include(:alternatives)
    expect(snapshot(appointment)).to eq(before_state)
    expect(before_state["lock_version"]).to eq(0)
    expect(appointment.reschedules.count).to eq(0)
    expect(events).to be_empty
  end

  describe "AC7 resource choice" do
    it "keeps the current bay and technician when both are free, even if the strategy would choose others" do
      other_bay = create(:service_bay, dealership:)
      other_tech = add_technician
      strategy = instance_double(Scheduling::AssignmentStrategies::LeastLoaded)
      allow(strategy).to receive(:choose)
        .and_return(Scheduling::Assignment.new(bay_id: other_bay.id, technician_id: other_tech.id))
      placement = Appointments::Placement.new(clock:, strategy:, slot_minutes: 15)

      described_class.new(clock:, placement:).call(
        appointment_id: appointment.id, params: { new_start_at: "2030-01-07T13:00:00Z" }
      )

      appointment.reload
      expect([ appointment.service_bay_id, appointment.technician_id ]).to eq([ bay.id, technician.id ])
      expect(strategy).not_to have_received(:choose)
    end

    it "picks another technician when the current one is on time off" do
      other_tech = add_technician
      create(:technician_time_off, technician:, start_at: Time.utc(2030, 1, 7, 12), end_at: Time.utc(2030, 1, 7, 15))

      result = reschedule(new_start_at: "2030-01-07T13:00:00Z")

      expect(result.value!.technician_id).to eq(other_tech.id)
    end
  end

  describe "EC5 invalid new time" do
    it "rejects a missing new_start_at" do
      result = reschedule

      expect(code_of(result)).to eq("VALIDATION_ERROR")
      expect(result.failure.last[:errors]).to include(new_start_at: be_present)
    end

    it "rejects a timestamp without an offset" do
      expect(code_of(reschedule(new_start_at: "2030-01-08T11:00:00"))).to eq("VALIDATION_ERROR")
    end

    {
      "2029-12-31T09:00:00Z" => "START_TIME_IN_PAST",
      "2030-01-07T11:10:00Z" => "START_TIME_NOT_ON_SLOT_GRID",
      "2030-01-07T22:00:00Z" => "OUTSIDE_OPENING_HOURS"
    }.each do |time, code|
      it "returns #{code} for #{time} and leaves the appointment unchanged" do
        before_state = snapshot(appointment)

        result = reschedule(new_start_at: time)

        expect(code_of(result)).to eq(code)
        expect(snapshot(appointment)).to eq(before_state)
      end
    end

    it "returns DEALERSHIP_CLOSED on a day with no opening hours" do
      expect(code_of(reschedule(new_start_at: "2030-01-08T11:00:00Z"))).to eq("DEALERSHIP_CLOSED")
    end
  end

  describe "EC6 only confirmed can be rescheduled" do
    it "rejects an in_progress appointment" do
      appointment.update!(status: "in_progress")

      result = reschedule(new_start_at: "2030-01-07T13:00:00Z")

      expect(code_of(result)).to eq("INVALID_STATUS_TRANSITION")
      expect(result.failure.last[:extra]).to eq({ allowed_transitions: [ "completed" ] })
      expect(appointment.reload.start_at).to eq(Time.utc(2030, 1, 7, 9))
    end

    it "rejects a cancelled appointment" do
      appointment.update!(status: "cancelled")

      result = reschedule(new_start_at: "2030-01-07T13:00:00Z")

      expect(code_of(result)).to eq("INVALID_STATUS_TRANSITION")
      expect(result.failure.last[:extra]).to eq({ allowed_transitions: [] })
      expect(appointment.reload.start_at).to eq(Time.utc(2030, 1, 7, 9))
    end
  end

  it "EC7 returns CONCURRENT_MODIFICATION for a stale lock_version" do
    appointment.update_columns(lock_version: 1)

    result = reschedule(new_start_at: "2030-01-07T13:00:00Z", lock_version: 0)

    expect(code_of(result)).to eq("CONCURRENT_MODIFICATION")
    expect(appointment.reload.start_at).to eq(Time.utc(2030, 1, 7, 9))
    expect(appointment.reschedules.count).to eq(0)
  end

  describe "EC8 the vehicle's other appointment" do
    let!(:second) do
      create(:appointment, dealership:, customer:, vehicle:, service_type:, technician:, service_bay: bay,
                           start_at: Time.utc(2030, 1, 7, 11), end_at: Time.utc(2030, 1, 7, 12))
    end

    it "conflicts and reports the other appointment id" do
      result = reschedule(new_start_at: "2030-01-07T10:30:00Z")

      expect(code_of(result)).to eq("VEHICLE_ALREADY_BOOKED")
      expect(result.failure.last[:extra]).to eq({ appointment_id: second.id })
    end

    it "does not conflict with itself" do
      expect(reschedule(new_start_at: "2030-01-07T09:15:00Z")).to be_success
    end
  end

  it "EC13 publishes nothing when the surrounding transaction rolls back" do
    events = capture_events do
      ApplicationRecord.transaction do
        reschedule(new_start_at: "2030-01-07T13:00:00Z")
        raise ActiveRecord::Rollback
      end
    end

    expect(events).to be_empty
    expect(appointment.reload.start_at).to eq(Time.utc(2030, 1, 7, 9))
    expect(appointment.reschedules.count).to eq(0)
  end

  it "fails with APPOINTMENT_NOT_FOUND for an unknown id" do
    result = service.call(appointment_id: "00000000-0000-0000-0000-000000000000",
                          params: { new_start_at: "2030-01-07T13:00:00Z" })

    expect(code_of(result)).to eq("APPOINTMENT_NOT_FOUND")
  end
end
