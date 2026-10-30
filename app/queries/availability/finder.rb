module Availability
  class Finder
    Candidates = Data.define(:bay_ids, :technician_ids, :technician_loads)

    def call(dealership:, service_type:, interval:)
      bay_ids = FreeBays.new(dealership:, service_type:, interval:).call.pluck(:id)
      technician_ids = FreeTechnicians.new(dealership:, service_type:, interval:).call.pluck(:id)
      Candidates.new(bay_ids:, technician_ids:, technician_loads: loads(dealership, technician_ids, interval))
    end

    private

    def loads(dealership, technician_ids, interval)
      return {} if technician_ids.empty?

      day_start = interval.starts_at.in_time_zone(dealership.time_zone).beginning_of_day
      Appointment.active
        .where(technician_id: technician_ids, start_at: day_start...(day_start + 1.day))
        .group(:technician_id)
        .count
    end
  end
end
