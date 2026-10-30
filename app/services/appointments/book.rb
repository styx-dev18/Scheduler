module Appointments
  class Book
    include Dry::Monads[:result]

    MAX_ASSIGNMENT_ATTEMPTS = 3
    BAY_CONSTRAINT = "appointments_no_bay_overlap".freeze
    TECHNICIAN_CONSTRAINT = "appointments_no_technician_overlap".freeze

    def initialize(clock: Clock, availability: Availability::Finder.new,
                   strategy: Scheduling::AssignmentStrategies::LeastLoaded.new,
                   slot_minutes: Integer(ENV.fetch("SLOT_MINUTES", "15")))
      @clock = clock
      @availability = availability
      @strategy = strategy
      @slot_minutes = slot_minutes
    end

    def call(params)
      form = BookingRequest.new(params)
      return fail_with("VALIDATION_ERROR", "Invalid booking request", errors: form.errors.to_hash) unless form.valid?

      starts_at = form.starts_at
      return fail_with("START_TIME_IN_PAST", "Start time must be in the future") if starts_at <= @clock.now
      unless Scheduling::SlotTime.aligned?(starts_at, @slot_minutes)
        return fail_with("START_TIME_NOT_ON_SLOT_GRID", "Start time must be on a #{@slot_minutes}-minute boundary")
      end

      customer = Customer.find_by(id: form.customer_id)
      return not_found("Customer", "customer_id") unless customer

      vehicle = Vehicle.find_by(id: form.vehicle_id)
      return not_found("Vehicle", "vehicle_id") unless vehicle

      service_type = ServiceType.find_by(id: form.service_type_id)
      return not_found("Service type", "service_type_id") unless service_type

      dealership = Dealership.find_by(id: form.dealership_id)
      return not_found("Dealership", "dealership_id") unless dealership

      if vehicle.customer_id != customer.id
        return fail_with("VEHICLE_OWNERSHIP_MISMATCH", "Vehicle does not belong to the customer")
      end

      interval = Scheduling::TimeInterval.from_slot(
        Scheduling::SlotTime.new(starts_at:, slot_minutes: @slot_minutes),
        duration_minutes: service_type.duration_minutes
      )

      case opening_policy(dealership).evaluate(interval)
      when :closed then return fail_with("DEALERSHIP_CLOSED", "The dealership is closed on that day")
      when :outside_hours then return fail_with("OUTSIDE_OPENING_HOURS", "The requested time is outside opening hours")
      end

      conflict = vehicle_conflict(vehicle, interval)
      return conflict if conflict

      ApplicationRecord.transaction do
        assign_and_persist(customer:, vehicle:, service_type:, dealership:, interval:)
      end
    end

    private

    def assign_and_persist(customer:, vehicle:, service_type:, dealership:, interval:)
      candidates = @availability.call(dealership:, service_type:, interval:)
      extra = { starts_at: interval.starts_at.utc.iso8601, ends_at: interval.ends_at.utc.iso8601 }

      if candidates.bay_ids.empty? || candidates.technician_ids.empty?
        conflict = vehicle_conflict(vehicle, interval)
        return conflict if conflict
      end

      if candidates.bay_ids.empty? && candidates.technician_ids.empty?
        return fail_with("NO_CAPACITY", "No service bay or technician is available", extra:)
      end
      return fail_with("NO_BAY", "No service bay is available", extra:) if candidates.bay_ids.empty?
      return fail_with("NO_TECHNICIAN", "No technician is available", extra:) if candidates.technician_ids.empty?

      bays = candidates.bay_ids.dup
      technicians = candidates.technician_ids.dup

      MAX_ASSIGNMENT_ATTEMPTS.times do
        assignment = @strategy.choose(bays:, technicians:, interval:, loads: candidates.technician_loads)
        return fail_with("NO_CAPACITY", "No service bay or technician is available", extra:) unless assignment

        begin
          return Success(create_appointment(customer:, vehicle:, service_type:, dealership:, interval:, assignment:))
        rescue ActiveRecord::StatementInvalid => e
          raise unless e.cause.is_a?(PG::ExclusionViolation)

          conflict = vehicle_conflict(vehicle, interval)
          return conflict if conflict

          case e.cause.result.error_field(PG::PG_DIAG_CONSTRAINT_NAME)
          when BAY_CONSTRAINT then bays -= [ assignment.bay_id ]
          when TECHNICIAN_CONSTRAINT then technicians -= [ assignment.technician_id ]
          end
          break if bays.empty? || technicians.empty?
        end
      end

      fail_with("NO_CAPACITY", "No service bay or technician is available", extra:)
    end

    def create_appointment(customer:, vehicle:, service_type:, dealership:, interval:, assignment:)
      Appointment.transaction(requires_new: true) do
        Appointment.create!(
          customer:, vehicle:, service_type:, dealership:,
          technician_id: assignment.technician_id,
          service_bay_id: assignment.bay_id,
          start_at: interval.starts_at,
          end_at: interval.ends_at
        )
      end
    end

    def vehicle_conflict(vehicle, interval)
      booked_id = Appointment.active.for_vehicle(vehicle.id).overlapping(interval).pick(:id)
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

    def not_found(resource, field)
      fail_with("NOT_FOUND", "#{resource} not found", errors: { field => [ "not found" ] })
    end

    def fail_with(code, detail, errors: nil, extra: nil)
      Failure([ code, { detail:, errors:, extra: } ])
    end
  end
end
