require "rails_helper"

RSpec.describe Appointments::Cancel do
  let(:now) { Time.utc(2030, 1, 1) }
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

  it "AC1 cancels a confirmed appointment and records the history row" do
    result = service.call(appointment_id: appointment.id, reason: "ac1")

    expect(result).to be_success
    appointment.reload
    aggregate_failures do
      expect(appointment.status).to eq("cancelled")
      expect(appointment.cancelled_at).to eq(now)
      expect(appointment.cancellation_reason).to eq("ac1")
      history = appointment.status_histories.sole
      expect([ history.from_status, history.to_status, history.changed_at, history.actor ])
        .to eq([ "confirmed", "cancelled", now, "customer" ])
    end
  end

  it "AC1 frees the bay and technician for another booking" do
    service.call(appointment_id: appointment.id)

    other = build(:appointment, dealership: appointment.dealership, technician: appointment.technician,
                                service_bay: appointment.service_bay)

    expect(other.save).to be(true)
  end

  it "AC2 returns the current state on a repeat cancel without a second history row or event" do
    events = capture_events do
      service.call(appointment_id: appointment.id, reason: "ac2")
      @repeat = service.call(appointment_id: appointment.id, reason: "ac2")
    end

    expect(@repeat).to be_success
    expect(@repeat.value!.status).to eq("cancelled")
    expect(appointment.status_histories.count).to eq(1)
    expect(events.map(&:first)).to eq([ "appointment.cancelled" ])
  end

  it "EC1 rejects cancelling a completed appointment" do
    completed = create(:appointment, status: "completed")

    events = capture_events { @result = service.call(appointment_id: completed.id) }

    expect(code_of(@result)).to eq("INVALID_STATUS_TRANSITION")
    expect(@result.failure.last[:extra]).to eq({ allowed_transitions: [] })
    expect(completed.reload.status).to eq("completed")
    expect(completed.status_histories.count).to eq(0)
    expect(events).to be_empty
  end

  it "EC2 fails with APPOINTMENT_NOT_FOUND for an unknown id" do
    result = service.call(appointment_id: "00000000-0000-0000-0000-000000000000")

    expect(code_of(result)).to eq("APPOINTMENT_NOT_FOUND")
  end

  describe "EC3 reason boundaries" do
    it "rejects a 501-character reason and leaves the appointment unchanged" do
      result = service.call(appointment_id: appointment.id, reason: "a" * 501)

      expect(code_of(result)).to eq("VALIDATION_ERROR")
      expect(result.failure.last[:errors]).to eq({ "reason" => [ "is too long (maximum is 500 characters)" ] })
      expect(appointment.reload.status).to eq("confirmed")
    end

    it "rejects a non-string reason and leaves the appointment unchanged" do
      result = service.call(appointment_id: appointment.id, reason: 123)

      expect(code_of(result)).to eq("VALIDATION_ERROR")
      expect(result.failure.last[:errors]).to eq({ "reason" => [ "must be a string" ] })
      expect(appointment.reload.status).to eq("confirmed")
    end

    it "accepts no reason and stores nil" do
      result = service.call(appointment_id: appointment.id)

      expect(result.value!.cancellation_reason).to be_nil
    end

    it "accepts a 500-character reason" do
      reason = "a" * 500

      expect(service.call(appointment_id: appointment.id, reason:).value!.cancellation_reason).to eq(reason)
    end
  end

  it "AC3 has the cut-off off by default" do
    soon = create(:appointment, start_at: now + 30.minutes, end_at: now + 90.minutes)

    result = described_class.new(clock:, cutoff_hours: 0).call(appointment_id: soon.id)

    expect(result.value!.status).to eq("cancelled")
  end

  describe "EC4 cut-off boundary" do
    let(:service) { described_class.new(clock:, cutoff_hours: 2) }

    it "blocks a cancel 1h59m before the start" do
      inside = create(:appointment, start_at: now + 119.minutes, end_at: now + 179.minutes)

      result = service.call(appointment_id: inside.id)

      expect(code_of(result)).to eq("CANCELLATION_WINDOW_CLOSED")
      expect(inside.reload.status).to eq("confirmed")
      expect(inside.status_histories.count).to eq(0)
    end

    it "allows a cancel exactly 2h before the start" do
      boundary = create(:appointment, start_at: now + 2.hours, end_at: now + 3.hours)

      expect(service.call(appointment_id: boundary.id).value!.status).to eq("cancelled")
    end
  end

  it "AC11 publishes one appointment.cancelled event with the correlation id" do
    Current.request_id = "req-ac11"

    events = capture_events { service.call(appointment_id: appointment.id, reason: "why") }

    name, payload = events.sole
    expect(name).to eq("appointment.cancelled")
    expect(payload).to include(appointment_id: appointment.id, start_at: appointment.start_at, end_at: appointment.end_at,
                               occurred_at: now, request_id: "req-ac11", cancelled_at: now, reason: "why")
  ensure
    Current.reset
  end

  it "EC13 publishes nothing and changes nothing when the surrounding transaction rolls back" do
    events = capture_events do
      ApplicationRecord.transaction do
        service.call(appointment_id: appointment.id)
        raise ActiveRecord::Rollback
      end
    end

    expect(events).to be_empty
    expect(appointment.reload.status).to eq("confirmed")
    expect(appointment.status_histories.count).to eq(0)
  end
end
