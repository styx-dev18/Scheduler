module Appointments
  class Placement
    include Dry::Monads[:result]

    MAX_ASSIGNMENT_ATTEMPTS = 3
    BAY_CONSTRAINT = "appointments_no_bay_overlap".freeze
    TECHNICIAN_CONSTRAINT = "appointments_no_technician_overlap".freeze

    def initialize(clock: Clock, availability: Availability::Finder.new,
                   strategy: Scheduling::AssignmentStrategies::LeastLoaded.new,
                   alternatives: Availability::Alternatives.new,
                   slot_minutes: Integer(ENV.fetch("SLOT_MINUTES", "15")))
      @clock = clock
      @availability = availability
      @strategy = strategy
      @alternatives = alternatives
      @slot_minutes = slot_minutes
    end

    def call(vehicle:, service_type:, dealership:, starts_at:, exclude_appointment_id: nil, preferred: nil, &persist)
      return fail_with("START_TIME_IN_PAST", "Start time must be in the future") if starts_at <= @clock.now
      unless Scheduling::SlotTime.aligned?(starts_at, @slot_minutes)
        return fail_with("START_TIME_NOT_ON_SLOT_GRID", "Start time must be on a #{@slot_minutes}-minute boundary")
      end

      interval = Scheduling::TimeInterval.from_slot(
        Scheduling::SlotTime.new(starts_at:, slot_minutes: @slot_minutes),
        duration_minutes: service_type.duration_minutes
      )

      case opening_policy(dealership).evaluate(interval)
      when :closed then return fail_with("DEALERSHIP_CLOSED", "The dealership is closed on that day")
      when :outside_hours then return fail_with("OUTSIDE_OPENING_HOURS", "The requested time is outside opening hours")
      end

      conflict = vehicle_conflict(vehicle, interval, exclude_appointment_id)
      return conflict if conflict

      ApplicationRecord.transaction do
        assign_and_persist(vehicle:, service_type:, dealership:, interval:, exclude_appointment_id:, preferred:, persist:)
      end
    end

    private

    def assign_and_persist(vehicle:, service_type:, dealership:, interval:, exclude_appointment_id:, preferred:, persist:)
      candidates = @availability.call(dealership:, service_type:, interval:, exclude_appointment_id:)

      if candidates.bay_ids.empty? || candidates.technician_ids.empty?
        conflict = vehicle_conflict(vehicle, interval, exclude_appointment_id)
        return conflict if conflict
      end

      if candidates.bay_ids.empty? && candidates.technician_ids.empty?
        return no_availability("NO_CAPACITY", "No service bay or technician is available", dealership:, service_type:, interval:)
      end
      if candidates.bay_ids.empty?
        return no_availability("NO_BAY", "No service bay is available", dealership:, service_type:, interval:)
      end
      if candidates.technician_ids.empty?
        return no_availability("NO_TECHNICIAN", "No technician is available", dealership:, service_type:, interval:)
      end

      bays = candidates.bay_ids.dup
      technicians = candidates.technician_ids.dup
      first_attempt = true

      MAX_ASSIGNMENT_ATTEMPTS.times do
        assignment = choose(first_attempt ? preferred : nil, bays:, technicians:, interval:, loads: candidates.technician_loads)
        first_attempt = false
        unless assignment
          return no_availability("NO_CAPACITY", "No service bay or technician is available", dealership:, service_type:, interval:)
        end

        begin
          record = ApplicationRecord.transaction(requires_new: true) { persist.call(assignment, interval) }
          return Success(record)
        rescue ActiveRecord::ExclusionViolation => e
          conflict = vehicle_conflict(vehicle, interval, exclude_appointment_id)
          return conflict if conflict

          case e.cause.result.error_field(PG::PG_DIAG_CONSTRAINT_NAME)
          when BAY_CONSTRAINT then bays -= [ assignment.bay_id ]
          when TECHNICIAN_CONSTRAINT then technicians -= [ assignment.technician_id ]
          end
          break if bays.empty? || technicians.empty?
        end
      end

      no_availability("NO_CAPACITY", "No service bay or technician is available", dealership:, service_type:, interval:)
    end

    def choose(preferred, bays:, technicians:, interval:, loads:)
      if preferred && bays.include?(preferred.bay_id) && technicians.include?(preferred.technician_id)
        return preferred
      end

      @strategy.choose(bays:, technicians:, interval:, loads:)
    end

    def no_availability(code, detail, dealership:, service_type:, interval:)
      fail_with(code, detail, extra: {
        starts_at: interval.starts_at.utc.iso8601,
        ends_at: interval.ends_at.utc.iso8601,
        alternatives: @alternatives.call(dealership:, service_type:, interval:)
      })
    end

    def vehicle_conflict(vehicle, interval, exclude_appointment_id)
      booked_id = Appointment.active.for_vehicle(vehicle.id).overlapping(interval)
        .where.not(id: exclude_appointment_id).pick(:id)
      return unless booked_id

      fail_with("VEHICLE_ALREADY_BOOKED", "The vehicle already has an appointment in that period",
                extra: { appointment_id: booked_id })
    end

    def opening_policy(dealership)
      Scheduling::OpeningHoursPolicy.new(
        zone: ActiveSupport::TimeZone[dealership.time_zone],
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

    def fail_with(code, detail, errors: nil, extra: nil)
      Failure([ code, { detail:, errors:, extra: } ])
    end
  end
end
