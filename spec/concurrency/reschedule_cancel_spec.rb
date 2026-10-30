require "rails_helper"

RSpec.describe "Appointment reschedule and cancel", "concurrency" do
  self.use_transactional_tests = false

  let!(:dealership) { create(:dealership) }
  let!(:customer) { create(:customer) }
  let!(:vehicle) { create(:vehicle, customer:) }
  let!(:qualification) { create(:qualification) }
  let!(:service_type) { create(:service_type, required_qualification: qualification) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:technician) { create(:technician, dealership:) }
  let!(:opening_hours) { [ 1, 2 ].map { |day| create(:dealership_opening_hour, dealership:, day_of_week: day) } }
  let!(:shifts) { [ 1, 2 ].map { |day| create(:technician_shift, technician:, day_of_week: day) } }
  let!(:technician_qualification) { create(:technician_qualification, technician:, qualification:) }
  let!(:appointment) do
    create(:appointment, dealership:, customer:, vehicle:, technician:, service_bay: bay, service_type:)
  end

  before { travel_to Time.utc(2030, 1, 1) }

  after do
    AppointmentReschedule.where(appointment_id: appointment.id).delete_all
    AppointmentStatusHistory.where(appointment_id: appointment.id).delete_all
    Appointment.where(id: appointment.id).delete_all
    technician_qualification.delete
    shifts.each(&:delete)
    opening_hours.each(&:delete)
    technician.delete
    bay.delete
    service_type.delete
    qualification.delete
    vehicle.delete
    customer.delete
    dealership.delete
  end

  def run_parallel(*actions)
    latch = Queue.new
    threads = actions.map do |action|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          latch.pop
          action.call
        end
      end
    end
    actions.size.times { latch << :go }
    threads.map(&:value)
  end

  it "EC9 serializes a reschedule and a cancel into one consistent end state over 5 rounds" do
    5.times do
      reschedule = -> { Appointments::Reschedule.new.call(appointment_id: appointment.id, params: { new_start_at: "2030-01-08T11:00:00Z" }) }
      cancel = -> { Appointments::Cancel.new.call(appointment_id: appointment.id) }

      reschedule_result, cancel_result = run_parallel(reschedule, cancel)
      appointment.reload

      aggregate_failures do
        expect(cancel_result).to be_success
        expect(appointment.status).to eq("cancelled")
        expect(appointment.status_histories.map { |row| [ row.from_status, row.to_status ] }).to eq([ %w[confirmed cancelled] ])
        if reschedule_result.success?
          expect(appointment.reschedules.count).to eq(1)
          expect(appointment.start_at).to eq(Time.utc(2030, 1, 8, 11))
        else
          expect(reschedule_result.failure.first).to eq("INVALID_STATUS_TRANSITION")
          expect(appointment.reschedules.count).to eq(0)
          expect(appointment.start_at).to eq(Time.utc(2030, 1, 7, 9))
        end
      end

      appointment.reschedules.delete_all
      appointment.status_histories.delete_all
      appointment.update_columns(status: "confirmed", cancelled_at: nil, cancellation_reason: nil,
                                 start_at: Time.utc(2030, 1, 7, 9), end_at: Time.utc(2030, 1, 7, 10))
    end
  end
end
