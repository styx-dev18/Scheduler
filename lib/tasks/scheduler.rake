namespace :scheduler do
  desc "Load a large, non-overlapping appointment data set for benchmarking"
  task :load_data, [ :count ] => :environment do |_task, args|
    count = Integer(args[:count] || 100_000)
    pairs = 20
    per_day = pairs * 9
    batch_size = 10_000
    zone = ActiveSupport::TimeZone["Europe/London"]
    first_day = Date.new(2030, 1, 1)
    now = Time.current
    uuid = ->(kind, number) { format("00000000-0000-4000-%04d-%012d", kind, number) }

    dealership_id = uuid.call(9000, 1)
    service_type_id = uuid.call(9000, 2)
    bay_ids = Array.new(pairs) { |k| uuid.call(9001, k) }
    technician_ids = Array.new(pairs) { |k| uuid.call(9002, k) }
    customer_ids = Array.new(pairs) { |k| uuid.call(9003, k) }
    vehicle_ids = Array.new(pairs) { |k| uuid.call(9004, k) }

    ActiveRecord::Base.transaction do
      appointment_ids = Appointment.where(dealership_id:).select(:id)
      AppointmentStatusHistory.where(appointment_id: appointment_ids).delete_all
      IdempotencyKey.where(appointment_id: appointment_ids).delete_all
      Appointment.where(dealership_id:).delete_all
      BayBlock.where(service_bay_id: bay_ids).delete_all
      TechnicianShift.where(technician_id: technician_ids).delete_all
      TechnicianTimeOff.where(technician_id: technician_ids).delete_all
      TechnicianQualification.where(technician_id: technician_ids).delete_all
      DealershipServiceType.where(dealership_id:).delete_all
      DealershipOpeningHour.where(dealership_id:).delete_all
      DealershipHoliday.where(dealership_id:).delete_all
      Technician.where(id: technician_ids).delete_all
      ServiceBay.where(id: bay_ids).delete_all
      Vehicle.where(id: vehicle_ids).delete_all
      Customer.where(id: customer_ids).delete_all
      ServiceType.where(id: service_type_id).delete_all
      Dealership.where(id: dealership_id).delete_all

      Dealership.insert_all([ { id: dealership_id, name: "Load Test Motors", time_zone: "Europe/London", created_at: now, updated_at: now } ])
      ServiceType.insert_all([ { id: service_type_id, name: "Load Test Service", description: "Load test", duration_minutes: 60, required_bay_type: "general", created_at: now, updated_at: now } ])
      DealershipServiceType.insert_all([ { dealership_id:, service_type_id:, created_at: now, updated_at: now } ])
      DealershipOpeningHour.insert_all((0..6).map { |day| { dealership_id:, day_of_week: day, opens_at: "08:00", closes_at: "17:00", created_at: now, updated_at: now } })
      ServiceBay.insert_all(bay_ids.each_with_index.map { |id, k| { id:, dealership_id:, name: "Load Bay #{k}", bay_type: "general", created_at: now, updated_at: now } })
      Technician.insert_all(technician_ids.each_with_index.map { |id, k| { id:, dealership_id:, name: "Load Technician #{k}", created_at: now, updated_at: now } })
      TechnicianShift.insert_all(technician_ids.product((0..6).to_a).map { |technician_id, day| { technician_id:, day_of_week: day, starts_at: "08:00", ends_at: "17:00", created_at: now, updated_at: now } })
      Customer.insert_all(customer_ids.each_with_index.map { |id, k| { id:, name: "Load Customer #{k}", email: "load-customer-#{k}@example.com", created_at: now, updated_at: now } })
      Vehicle.insert_all(vehicle_ids.each_with_index.map { |id, k| { id:, customer_id: customer_ids[k], vin: "LOADTEST#{k.to_s.rjust(9, '0')}", make: "Load", model: "Test", created_at: now, updated_at: now } })

      (0...count).each_slice(batch_size) do |indexes|
        rows = indexes.map do |i|
          k = i % pairs
          date = first_day + (i / per_day)
          start_at = zone.local(date.year, date.month, date.day, 8 + (i % per_day) / pairs)
          {
            customer_id: customer_ids[k], vehicle_id: vehicle_ids[k], technician_id: technician_ids[k],
            service_bay_id: bay_ids[k], service_type_id:, dealership_id:,
            start_at:, end_at: start_at + 1.hour, status: "confirmed", created_at: now, updated_at: now
          }
        end
        Appointment.insert_all(rows)
      end
    end
  end
end
