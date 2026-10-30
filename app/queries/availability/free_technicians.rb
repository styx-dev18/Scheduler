module Availability
  class FreeTechnicians
    TIME_FORMAT = "%H:%M:%S".freeze

    def initialize(dealership:, service_type:, interval:)
      @dealership = dealership
      @service_type = service_type
      @interval = interval
    end

    def call
      local_start = @interval.starts_at.in_time_zone(@dealership.time_zone)
      local_end = @interval.ends_at.in_time_zone(@dealership.time_zone)
      return Technician.none unless local_start.to_date == local_end.to_date

      scope = @dealership.technicians
        .where(active: true)
        .where(id: covering_shifts(local_start, local_end).select(:technician_id))
        .where.not(id: TechnicianTimeOff.where("start_at < ? AND end_at > ?", @interval.ends_at, @interval.starts_at).select(:technician_id))
        .where.not(id: Appointment.active.overlapping(@interval).select(:technician_id))
      scope = scope.where(id: qualified) if @service_type.required_qualification_id.present?
      scope.distinct.order(:id)
    end

    private

    def covering_shifts(local_start, local_end)
      TechnicianShift.where(day_of_week: local_start.wday)
        .where("starts_at <= ? AND ends_at >= ?", local_start.strftime(TIME_FORMAT), local_end.strftime(TIME_FORMAT))
    end

    def qualified
      TechnicianQualification.where(qualification_id: @service_type.required_qualification_id).select(:technician_id)
    end
  end
end
