require "rails_helper"

RSpec.describe Appointments::Events do
  let(:occurred_at) { Time.utc(2030, 1, 1) }
  let(:received) { [] }

  around do |example|
    ActiveSupport::Notifications.subscribed(->(*args) { received << ActiveSupport::Notifications::Event.new(*args) }, /\Aappointment\./) do
      example.run
    end
  end

  after { Current.reset }

  it "AC11 publishes the base payload with the request id" do
    appointment = create(:appointment)
    Current.request_id = "req-ac11"

    result = described_class.publish(described_class::CONFIRMED, appointment, occurred_at:)

    expect(result).to be_nil
    expect(received.size).to eq(1)
    expect(received.first.name).to eq("appointment.confirmed")
    expect(received.first.payload).to eq(
      appointment_id: appointment.id,
      customer_id: appointment.customer_id,
      dealership_id: appointment.dealership_id,
      status: "confirmed",
      start_at: appointment.start_at,
      end_at: appointment.end_at,
      occurred_at:,
      request_id: "req-ac11"
    )
  end

  it "AC11 merges event specific extras" do
    appointment = create(:appointment)

    described_class.publish(described_class::STATUS_CHANGED, appointment, occurred_at:,
                            from_status: "confirmed", to_status: "in_progress")

    expect(received.first.name).to eq("appointment.status_changed")
    expect(received.first.payload).to include(from_status: "confirmed", to_status: "in_progress")
  end

  it "AC11 carries a nil request id outside a request" do
    described_class.publish(described_class::CANCELLED, create(:appointment), occurred_at:,
                            cancelled_at: occurred_at, reason: nil)

    expect(received.first.payload).to include(request_id: nil, cancelled_at: occurred_at, reason: nil)
  end

  it "AC11 uses the four documented event names" do
    expect([ described_class::CONFIRMED, described_class::RESCHEDULED, described_class::CANCELLED, described_class::STATUS_CHANGED ])
      .to eq(%w[appointment.confirmed appointment.rescheduled appointment.cancelled appointment.status_changed])
  end

  it "EC13 publishes nothing when the surrounding transaction rolls back" do
    appointment = create(:appointment)

    ApplicationRecord.transaction do
      described_class.publish(described_class::CONFIRMED, appointment, occurred_at:)
      raise ActiveRecord::Rollback
    end

    expect(received).to be_empty
  end

  it "EC13 publishes after the outermost transaction commits, not before" do
    appointment = create(:appointment)
    seen_inside = nil

    ApplicationRecord.transaction do
      ApplicationRecord.transaction(requires_new: true) do
        described_class.publish(described_class::CONFIRMED, appointment, occurred_at:)
      end
      seen_inside = received.size
    end

    expect(seen_inside).to eq(0)
    expect(received.size).to eq(1)
  end

  it "EC13 Cancel inside a rolled-back transaction publishes nothing and changes nothing" do
    appointment = create(:appointment)
    clock = class_double(Clock, now: occurred_at)

    ApplicationRecord.transaction do
      Appointments::Cancel.new(clock:).call(appointment_id: appointment.id)
      raise ActiveRecord::Rollback
    end

    expect(received).to be_empty
    expect(appointment.reload.status).to eq("confirmed")
    expect(appointment.status_histories.count).to eq(0)
  end

  it "EC13 ChangeStatus inside a rolled-back transaction publishes nothing and changes nothing" do
    appointment = create(:appointment)
    clock = class_double(Clock, now: occurred_at)

    ApplicationRecord.transaction do
      Appointments::ChangeStatus.new(clock:).call(appointment_id: appointment.id, status: "in_progress")
      raise ActiveRecord::Rollback
    end

    expect(received).to be_empty
    expect(appointment.reload.status).to eq("confirmed")
    expect(appointment.status_histories.count).to eq(0)
  end

  it "AC12 logs one JSON line per event through the initializer subscriber" do
    appointment = create(:appointment)
    Current.request_id = "req-ac12"
    lines = []
    allow(Rails.logger).to receive(:info) { |line| lines << line }

    described_class.publish(described_class::CANCELLED, appointment, occurred_at:,
                            cancelled_at: occurred_at, reason: "ac12")

    parsed = lines.filter_map { |line| JSON.parse(line) if line.is_a?(String) && line.start_with?("{") }
    expect(parsed.size).to eq(1)
    expect(parsed.first).to include(
      "event" => "appointment.cancelled",
      "appointment_id" => appointment.id,
      "request_id" => "req-ac12",
      "reason" => "ac12"
    )
  end

  it "AC13 documents the four events and the outbox path in the system design" do
    section = File.read(Rails.root.join("docs/system-design.md"))[/^## Appointment lifecycle and domain events.*?(?=^## )/m]

    expect(section).to be_present
    %w[appointment.confirmed appointment.rescheduled appointment.cancelled appointment.status_changed].each do |name|
      expect(section).to include(name)
    end
    expect(section).to match(/outbox/i)
    expect(section).to include("Solid Queue")
    expect(section).to match(/same transaction/)
  end
end
