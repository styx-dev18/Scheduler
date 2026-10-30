require "rails_helper"

RSpec.describe Appointments::ChangeStatus do
  let(:now) { Time.utc(2030, 1, 7, 9, 5) }
  let(:clock) { class_double(Clock, now:) }
  let(:service) { described_class.new(clock:) }
  let!(:appointment) { create(:appointment) }

  def capture_events
    events = []
    handler = ->(name, _start, _finish, _id, payload) { events << [ name, payload ] }
    ActiveSupport::Notifications.subscribed(handler, /\Aappointment\./) { yield }
    events
  end

  def code_of(result)
    result.failure.first
  end

  it "AC8 moves confirmed to in_progress to completed with history rows and events" do
    events = capture_events do
      @first = service.call(appointment_id: appointment.id, status: "in_progress")
      @second = service.call(appointment_id: appointment.id, status: "completed")
    end

    expect([ @first, @second ]).to all(be_success)
    expect(appointment.reload.status).to eq("completed")
    expect(appointment.status_histories.map { |h| [ h.from_status, h.to_status, h.changed_at, h.actor ] })
      .to match_array([ [ "confirmed", "in_progress", now, "staff" ], [ "in_progress", "completed", now, "staff" ] ])
    expect(events.map { |name, payload| [ name, payload[:from_status], payload[:to_status] ] })
      .to eq([ [ "appointment.status_changed", "confirmed", "in_progress" ],
               [ "appointment.status_changed", "in_progress", "completed" ] ])
  end

  it "AC9 records a no-show exactly at the start time" do
    result = described_class.new(clock: class_double(Clock, now: Time.utc(2030, 1, 7, 9))).call(
      appointment_id: appointment.id, status: "no_show"
    )

    expect(result.value!.status).to eq("no_show")
    history = appointment.status_histories.sole
    expect([ history.from_status, history.to_status ]).to eq([ "confirmed", "no_show" ])
  end

  it "EC10 rejects a no-show one second before the start" do
    early = described_class.new(clock: class_double(Clock, now: Time.utc(2030, 1, 7, 8, 59, 59)))

    result = early.call(appointment_id: appointment.id, status: "no_show")

    expect(code_of(result)).to eq("INVALID_STATUS_TRANSITION")
    expect(result.failure.last[:extra]).to eq({ allowed_transitions: %w[in_progress cancelled no_show] })
    expect(result.failure.last[:detail]).to eq("No-show can only be recorded after the start time")
    expect(appointment.reload.status).to eq("confirmed")
    expect(appointment.status_histories.count).to eq(0)
  end

  describe "EC11 invalid transitions" do
    it "rejects confirmed to completed with the allowed list" do
      result = service.call(appointment_id: appointment.id, status: "completed")

      expect(code_of(result)).to eq("INVALID_STATUS_TRANSITION")
      expect(result.failure.last[:extra]).to eq({ allowed_transitions: %w[in_progress cancelled no_show] })
      expect(appointment.reload.status).to eq("confirmed")
    end

    it "rejects completed to in_progress with an empty list" do
      completed = create(:appointment, status: "completed")

      result = service.call(appointment_id: completed.id, status: "in_progress")

      expect(code_of(result)).to eq("INVALID_STATUS_TRANSITION")
      expect(result.failure.last[:extra]).to eq({ allowed_transitions: [] })
      expect(completed.reload.status).to eq("completed")
    end
  end

  describe "EC12 bad input" do
    it "rejects an unknown status" do
      result = service.call(appointment_id: appointment.id, status: "bogus")

      expect(code_of(result)).to eq("VALIDATION_ERROR")
      expect(result.failure.last[:errors]).to eq({ "status" => [ "is not included in the list" ] })
    end

    it "rejects cancelled as a target" do
      expect(code_of(service.call(appointment_id: appointment.id, status: "cancelled"))).to eq("VALIDATION_ERROR")
      expect(appointment.reload.status).to eq("confirmed")
    end

    it "fails with APPOINTMENT_NOT_FOUND for an unknown id" do
      result = service.call(appointment_id: "00000000-0000-0000-0000-000000000000", status: "in_progress")

      expect(code_of(result)).to eq("APPOINTMENT_NOT_FOUND")
    end
  end

  it "AC11 publishes one status_changed event with the correlation id" do
    Current.request_id = "req-ac11"

    events = capture_events { service.call(appointment_id: appointment.id, status: "in_progress") }

    name, payload = events.sole
    expect(name).to eq("appointment.status_changed")
    expect(payload).to include(appointment_id: appointment.id, occurred_at: now, request_id: "req-ac11",
                               from_status: "confirmed", to_status: "in_progress")
  ensure
    Current.reset
  end

  it "EC13 publishes nothing and changes nothing when the surrounding transaction rolls back" do
    events = capture_events do
      ApplicationRecord.transaction do
        service.call(appointment_id: appointment.id, status: "in_progress")
        raise ActiveRecord::Rollback
      end
    end

    expect(events).to be_empty
    expect(appointment.reload.status).to eq("confirmed")
    expect(appointment.status_histories.count).to eq(0)
  end
end
