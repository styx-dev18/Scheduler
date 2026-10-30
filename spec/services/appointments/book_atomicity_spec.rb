require "rails_helper"

RSpec.describe Appointments::Book, "atomicity" do
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
    ActiveSupport::Notifications.subscribe(described_class::CONFIRMED_EVENT) { |*args| events << args.last }
  end

  before do
    create(:dealership_opening_hour, dealership:)
    create(:technician_shift, technician:)
    subscriber
  end

  after { ActiveSupport::Notifications.unsubscribe(subscriber) }

  def counts
    [ Appointment.count, IdempotencyKey.count ]
  end

  it "AC3 leaves nothing behind when the assignment strategy raises" do
    strategy = instance_double(Scheduling::AssignmentStrategies::LeastLoaded)
    allow(strategy).to receive(:choose).and_raise(RuntimeError, "assignment failed")
    service = Appointments::IdempotentBook.new(book: described_class.new(strategy:))

    expect { service.call(key: "key-ac3-assign", params:) }.to raise_error(RuntimeError, "assignment failed")

    expect(counts).to eq([ 0, 0 ])
    expect(events).to be_empty
  end

  it "AC3 leaves nothing behind when the appointment insert fails" do
    strategy = instance_double(Scheduling::AssignmentStrategies::LeastLoaded)
    allow(strategy).to receive(:choose).and_return(Scheduling::Assignment.new(bay_id: SecureRandom.uuid, technician_id: technician.id))
    service = Appointments::IdempotentBook.new(book: described_class.new(strategy:))

    expect { service.call(key: "key-ac3-insert", params:) }.to raise_error(ActiveRecord::RecordInvalid)

    expect(counts).to eq([ 0, 0 ])
    expect(events).to be_empty
  end

  it "AC3 and EC2 leave nothing behind and publish nothing when the idempotency write fails" do
    real_book = described_class.new
    book = instance_double(described_class)
    allow(book).to receive(:call) do |book_params|
      booked = real_book.call(book_params).value!
      Dry::Monads::Success(Appointment.new(id: SecureRandom.uuid, customer: booked.customer, vehicle: booked.vehicle,
                                           service_type: booked.service_type, dealership: booked.dealership,
                                           technician: booked.technician, service_bay: booked.service_bay,
                                           start_at: booked.start_at, end_at: booked.end_at, status: "confirmed"))
    end
    service = Appointments::IdempotentBook.new(book:)

    expect { service.call(key: "key-ec2", params:) }.to raise_error(ActiveRecord::StatementInvalid, /foreign key/i)

    expect(counts).to eq([ 0, 0 ])
    expect(events).to be_empty
  end
end
