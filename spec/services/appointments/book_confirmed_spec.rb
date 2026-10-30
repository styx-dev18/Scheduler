require "rails_helper"

RSpec.describe Appointments::Book, "confirmed appointment" do
  let(:dealership) { create(:dealership) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let(:service_type) { create(:service_type) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:technician) { create(:technician, dealership:) }
  let(:params) do
    {
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      service_type_id: service_type.id,
      dealership_id: dealership.id,
      start_at: "2030-01-07T09:00:00Z"
    }
  end
  let(:events) { [] }
  let(:subscriber) do
    ActiveSupport::Notifications.subscribe(described_class::CONFIRMED_EVENT) do |*args|
      payload = args.last
      events << payload.merge(
        row_visible: Appointment.exists?(payload[:appointment_id]),
        key_completed: IdempotencyKey.where.not(response_status: nil).exists?
      )
    end
  end

  before do
    create(:dealership_opening_hour, dealership:)
    create(:technician_shift, technician:)
    subscriber
  end

  after { ActiveSupport::Notifications.unsubscribe(subscriber) }

  it "AC1 persists a confirmed appointment with every foreign key and timestamp" do
    result = described_class.new.call(params)

    expect(result).to be_success
    expect(Appointment.count).to eq(1)
    appointment = Appointment.last
    aggregate_failures do
      expect(appointment.status).to eq("confirmed")
      expect(appointment.customer_id).to eq(customer.id)
      expect(appointment.vehicle_id).to eq(vehicle.id)
      expect(appointment.service_type_id).to eq(service_type.id)
      expect(appointment.dealership_id).to eq(dealership.id)
      expect(appointment.technician_id).to eq(technician.id)
      expect(appointment.service_bay_id).to eq(bay.id)
      expect(appointment.start_at).to eq(Time.utc(2030, 1, 7, 9))
      expect(appointment.end_at).to eq(Time.utc(2030, 1, 7, 9) + service_type.duration_minutes.minutes)
      expect(appointment.lock_version).to eq(0)
      expect(appointment.created_at).to be_present
      expect(appointment.updated_at).to be_present
    end
  end

  it "AC2 publishes the event once after commit and not again on an idempotent replay" do
    service = Appointments::IdempotentBook.new

    first = service.call(key: "key-ac2", params:)
    second = service.call(key: "key-ac2", params:)

    expect(first).to be_success
    expect(second).to be_success
    expect(events.size).to eq(1)
    event = events.first
    aggregate_failures do
      expect(event[:appointment_id]).to eq(Appointment.last.id)
      expect(event[:customer_id]).to eq(customer.id)
      expect(event[:dealership_id]).to eq(dealership.id)
      expect(event[:start_at]).to eq(Time.utc(2030, 1, 7, 9))
      expect(event[:row_visible]).to be(true)
      expect(event[:key_completed]).to be(true)
    end
  end

  it "AC2 publishes the event once for a booking without an idempotency key" do
    described_class.new.call(params)

    expect(events.map { |event| event[:appointment_id] }).to eq([ Appointment.last.id ])
  end

  it "EC1 publishes no event when the only bay is booked by another vehicle" do
    other_technician = create(:technician, dealership:)
    create(:appointment, dealership:, customer:, vehicle: create(:vehicle, customer:), technician: other_technician, service_bay: bay, service_type:)

    result = Appointments::IdempotentBook.new.call(key: "key-ec1", params:)

    expect(result.failure.first).to eq("NO_BAY")
    expect(events).to be_empty
    expect(Appointment.count).to eq(1)
  end

  it "EC1 publishes no event for a validation failure" do
    result = described_class.new.call(params.merge(vehicle_id: "not-a-uuid"))

    expect(result.failure.first).to eq("VALIDATION_ERROR")
    expect(events).to be_empty
  end
end
