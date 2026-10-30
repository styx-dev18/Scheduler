require "rails_helper"

RSpec.describe Appointments::Book, "concurrency" do
  self.use_transactional_tests = false

  let(:thread_count) { 2 }

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
          described_class.new.call(params)
        end
      end
    end
    thread_count.times { latch << :go }
    threads.map(&:value)
  end

  it "books the same vehicle and slot once and rejects the loser with VEHICLE_ALREADY_BOOKED" do
    successes, failures = run_parallel.partition(&:success?)

    expect(successes.count).to eq(1)
    expect(failures.map { |result| result.failure.first }).to eq([ "VEHICLE_ALREADY_BOOKED" ])
    expect(Appointment.where(customer_id: customer.id).count).to eq(1)
  end
end
