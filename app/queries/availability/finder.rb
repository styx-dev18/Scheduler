module Availability
  class Finder
    Candidates = Data.define(:bay_ids, :technician_ids, :technician_loads)

    def call(dealership:, service_type:, interval:, exclude_appointment_id: nil)
      bay_ids = FreeBays.new(dealership:, service_type:, interval:, exclude_appointment_id:).ids
      technician_ids = FreeTechnicians.new(dealership:, service_type:, interval:, exclude_appointment_id:).ids
      Candidates.new(bay_ids:, technician_ids:, technician_loads: loads(dealership, technician_ids, interval, exclude_appointment_id))
    end

    private

    def loads(dealership, technician_ids, interval, exclude_appointment_id)
      return {} if technician_ids.empty?

      day_start = interval.starts_at.in_time_zone(dealership.time_zone).beginning_of_day
      Appointment.active.where.not(id: exclude_appointment_id)
        .where(technician_id: technician_ids, start_at: day_start...(day_start + 1.day))
        .group(:technician_id)
        .count
    end
  end
end
