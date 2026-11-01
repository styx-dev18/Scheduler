require "rails_helper"

RSpec.describe Appointments::Book, "concurrency" do
  self.use_transactional_tests = false

  let(:thread_count) { 20 }
  let(:rounds) { Integer(ENV.fetch("RACE_ITERATIONS", "5")) }

  let!(:dealership) { create(:dealership) }
  let!(:customer) { create(:customer) }
  let!(:vehicles) { Array.new(thread_count) { create(:vehicle, customer:) } }
  let!(:service_type) { create(:service_type) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:technician) { create(:technician, dealership:) }
  let!(:opening_hour) { create(:dealership_opening_hour, dealership:) }
  let!(:shift) { create(:technician_shift, technician:) }

  def params_for(vehicle)
    {
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      service_type_id: service_type.id,
      dealership_id: dealership.id,
      start_at: "2030-01-07T09:00:00Z"
    }
  end

  def delete_appointments
    ids = Appointment.where(customer_id: customer.id).pluck(:id)
    AppointmentStatusHistory.where(appointment_id: ids).delete_all
    Appointment.where(id: ids).delete_all
  end

  after do
    delete_appointments
    shift.delete
    opening_hour.delete
    technician.delete
    bay.delete
    service_type.delete
    Vehicle.where(customer_id: customer.id).delete_all
    customer.delete
    dealership.delete
  end

  def run_parallel(targets)
    ready = Concurrent::CountDownLatch.new(targets.size)
    go = Concurrent::CountDownLatch.new(1)
    threads = targets.map do |vehicle|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready.count_down
          go.wait
          described_class.new.call(params_for(vehicle))
        end
      end
    end
    ready.wait(10)
    go.count_down
    threads.map(&:value)
  end

  it "AC7 books the last slot once and rejects 19 racers with a 409 over RACE_ITERATIONS rounds" do
    expect(ActiveRecord::Base.connection_pool.size).to be >= thread_count + 1

    rounds.times do
      successes, failures = run_parallel(vehicles).partition(&:success?)

      expect(successes.count).to eq(1)
      expect(failures.count).to eq(thread_count - 1)
      expect(failures.map { |result| ErrorCatalogue.fetch(result.failure.first).status }).to all(eq(409))
      expect(failures.map { |result| result.failure.first }).to all(satisfy { |code| %w[NO_BAY NO_TECHNICIAN NO_CAPACITY].include?(code) })
      expect(Appointment.active.where(customer_id: customer.id).count).to eq(1)

      delete_appointments
    end
  end

  it "EC3 books the same vehicle once and rejects 19 racers with VEHICLE_ALREADY_BOOKED" do
    successes, failures = run_parallel(Array.new(thread_count) { vehicles.first }).partition(&:success?)

    expect(successes.count).to eq(1)
    expect(failures.map { |result| result.failure.first }).to eq(Array.new(thread_count - 1, "VEHICLE_ALREADY_BOOKED"))
    expect(Appointment.where(customer_id: customer.id).count).to eq(1)
  end
end
