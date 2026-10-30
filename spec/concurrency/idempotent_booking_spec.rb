require "rails_helper"

RSpec.describe Appointments::IdempotentBook, "concurrency" do
  self.use_transactional_tests = false

  let(:thread_count) { 10 }
  let(:key) { "idem-ec16" }

  let!(:dealership) { create(:dealership) }
  let!(:customer) { create(:customer) }
  let!(:vehicle) { create(:vehicle, customer:) }
  let!(:service_type) { create(:service_type) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:technician) { create(:technician, dealership:) }
  let!(:opening_hour) { create(:dealership_opening_hour, dealership:) }
  let!(:shift) { create(:technician_shift, technician:) }
  let(:params) do
    {
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      service_type_id: service_type.id,
      dealership_id: dealership.id,
      start_at: "2030-01-07T09:00:00Z"
    }
  end

  after do
    IdempotencyKey.where(key:).delete_all
    Appointment.where(customer_id: customer.id).each do |appointment|
      AppointmentStatusHistory.where(appointment_id: appointment.id).delete_all
      appointment.delete
    end
    shift.delete
    opening_hour.delete
    technician.delete
    bay.delete
    service_type.delete
    vehicle.delete
    customer.delete
    dealership.delete
  end

  def run_parallel
    latch = Queue.new
    threads = Array.new(thread_count) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          latch.pop
          described_class.new.call(key:, params:)
        end
      end
    end
    thread_count.times { latch << :go }
    threads.map(&:value)
  end

  it "EC16 creates one appointment and one key row for parallel duplicates" do
    results = run_parallel

    expect(Appointment.where(customer_id: customer.id).count).to eq(1)
    expect(IdempotencyKey.where(key:).count).to eq(1)

    appointment_id = Appointment.find_by!(customer_id: customer.id).id.to_s
    successes, failures = results.partition(&:success?)
    expect(successes).not_to be_empty
    expect(successes.map { |r| r.value!.deep_stringify_keys["id"].to_s }.uniq).to eq([ appointment_id ])
    expect(failures.map { |r| r.failure.first }.uniq - [ "IDEMPOTENCY_KEY_IN_PROGRESS" ]).to be_empty
  end
end
