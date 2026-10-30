module Availability
  class DaySlots
    METRIC_EVENT = "availability.scheduler".freeze

    def initialize(clock: Clock, slot_minutes: Integer(ENV.fetch("SLOT_MINUTES", "15")))
      @clock = clock
      @slot_minutes = slot_minutes
    end

    def call(dealership:, service_type:, date:)
      ActiveSupport::Notifications.instrument(METRIC_EVENT) do
        slots(dealership:, service_type:, date:)
      end
    end

    private

    def slots(dealership:, service_type:, date:)
      zone = ActiveSupport::TimeZone[dealership.time_zone]
      following = date + 1
      day = Scheduling::TimeInterval.new(
        starts_at: zone.local(date.year, date.month, date.day),
        ends_at: zone.local(following.year, following.month, following.day)
      )
      intervals = candidates(dealership:, service_type:, zone:, day:)
      return [] if intervals.empty?

      bays = bay_busy(dealership:, service_type:, day:)
      technicians = technician_busy(dealership:, service_type:, date:, day:)
      appointments = appointment_rows(dealership:, day:)

      intervals.select do |interval|
        free_bay?(bays, appointments, interval) && free_technician?(technicians, appointments, zone, interval)
      end
    end

    def candidates(dealership:, service_type:, zone:, day:)
      policy = opening_policy(dealership, zone)
      step = @slot_minutes * 60
      first = (day.starts_at.to_i.to_r / step).ceil * step
      now = @clock.now
      duration = service_type.duration_minutes * 60

      (first...day.ends_at.to_i).step(step).filter_map do |epoch|
        start = Time.at(epoch).utc
        next unless Scheduling::SlotTime.aligned?(start, @slot_minutes) && start > now

        interval = Scheduling::TimeInterval.new(starts_at: start, ends_at: start + duration)
        interval if policy.evaluate(interval) == :open
      end
    end

    def opening_policy(dealership, zone)
      Scheduling::OpeningHoursPolicy.new(
        zone:,
        opening_hours: dealership.opening_hours.map do |hours|
          {
            day_of_week: hours.day_of_week,
            opens_at: hours.opens_at.strftime("%H:%M"),
            closes_at: hours.closes_at.strftime("%H:%M")
          }
        end,
        holidays: dealership.holidays.pluck(:holiday_on)
      )
    end

    def bay_busy(dealership:, service_type:, day:)
      bay_ids = dealership.service_bays.where(active: true, bay_type: service_type.required_bay_type).pluck(:id)
      blocks = BayBlock.where(service_bay_id: bay_ids)
        .where("start_at < ? AND end_at > ?", day.ends_at, day.starts_at)
        .pluck(:service_bay_id, :start_at, :end_at)
        .group_by(&:first)
      bay_ids.index_with { |id| (blocks[id] || []).map { |_, start_at, end_at| range(start_at, end_at) } }
    end

    def technician_busy(dealership:, service_type:, date:, day:)
      scope = dealership.technicians.where(active: true)
      if service_type.required_qualification_id.present?
        scope = scope.where(id: TechnicianQualification.where(qualification_id: service_type.required_qualification_id).select(:technician_id))
      end
      ids = scope.pluck(:id)
      shifts = TechnicianShift.where(technician_id: ids, day_of_week: date.wday)
        .pluck(:technician_id, :starts_at, :ends_at)
        .group_by(&:first)
      time_off = TechnicianTimeOff.where(technician_id: ids)
        .where("start_at < ? AND end_at > ?", day.ends_at, day.starts_at)
        .pluck(:technician_id, :start_at, :end_at)
        .group_by(&:first)

      ids.index_with do |id|
        {
          shifts: (shifts[id] || []).map { |_, starts_at, ends_at| [ seconds_of_day(starts_at), seconds_of_day(ends_at) ] },
          time_off: (time_off[id] || []).map { |_, start_at, end_at| range(start_at, end_at) }
        }
      end
    end

    def appointment_rows(dealership:, day:)
      rows = Appointment.active.where(dealership_id: dealership.id).overlapping(day)
        .pluck(:service_bay_id, :technician_id, :start_at, :end_at)
      {
        bay: rows.group_by(&:first).transform_values { |list| list.map { |_, _, start_at, end_at| range(start_at, end_at) } },
        technician: rows.group_by { |row| row[1] }.transform_values { |list| list.map { |_, _, start_at, end_at| range(start_at, end_at) } }
      }
    end

    def free_bay?(bays, appointments, interval)
      bays.any? do |id, blocks|
        (blocks + appointments[:bay].fetch(id, [])).none? { |busy| busy.overlaps?(interval) }
      end
    end

    def free_technician?(technicians, appointments, zone, interval)
      local_start = seconds_of_day(interval.starts_at.in_time_zone(zone))
      local_end = seconds_of_day(interval.ends_at.in_time_zone(zone))
      technicians.any? do |id, data|
        data[:shifts].any? { |opens, closes| opens <= local_start && local_end <= closes } &&
          (data[:time_off] + appointments[:technician].fetch(id, [])).none? { |busy| busy.overlaps?(interval) }
      end
    end

    def range(start_at, end_at)
      Scheduling::TimeInterval.new(starts_at: start_at, ends_at: end_at)
    end

    def seconds_of_day(time)
      time.hour * 3600 + time.min * 60 + time.sec
    end
  end
end
