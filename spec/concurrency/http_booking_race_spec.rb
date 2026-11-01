require "rails_helper"

RSpec.describe "POST /api/v1/appointments race" do
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
          session = ActionDispatch::Integration::Session.new(Rails.application)
          ready.count_down
          go.wait
          session.post "/api/v1/appointments", params: params_for(vehicle)
          [ session.response.status, JSON.parse(session.response.body).dig("error", "code") ]
        end
      end
    end
    ready.wait(10)
    go.count_down
    threads.map(&:value)
  end

  it "books the last slot once and rejects 19 racers with a 409 over RACE_ITERATIONS rounds" do
    expect(ActiveRecord::Base.connection_pool.size).to be >= thread_count + 1
    Rails.application.eager_load!

    rounds.times do
      results = run_parallel(vehicles)

      expect(results.map(&:first).tally).to eq(201 => 1, 409 => thread_count - 1)
      codes = results.select { |status, _| status == 409 }.map(&:last)
      expect(codes).to all(satisfy { |code| %w[NO_BAY NO_TECHNICIAN NO_CAPACITY].include?(code) })
      expect(Appointment.active.where(customer_id: customer.id).count).to eq(1)

      delete_appointments
    end
  end
end
