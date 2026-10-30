module Appointments
  class Book
    include Dry::Monads[:result]

    CONFIRMED_EVENT = Events::CONFIRMED
    METRIC_EVENT = "booking.scheduler".freeze
    BACKOFF_BASE_SECONDS = 0.02
    BACKOFF_CAP_SECONDS = 0.2

    def initialize(clock: Clock, availability: Availability::Finder.new,
                   strategy: Scheduling::AssignmentStrategies::LeastLoaded.new,
                   alternatives: Availability::Alternatives.new,
                   slot_minutes: Integer(ENV.fetch("SLOT_MINUTES", "15")),
                   jitter: -> { rand }, sleeper: ->(seconds) { sleep(seconds) })
      @clock = clock
      @jitter = jitter
      @sleeper = sleeper
      @placement = Placement.new(clock:, availability:, strategy:, alternatives:, slot_minutes:)
    end

    def call(params)
      ActiveSupport::Notifications.instrument(METRIC_EVENT) do |payload|
        result = perform(params)
        payload[:failure_code] = result.failure.first if result.failure?
        result
      end
    end

    private

    def perform(params)
      form = BookingRequest.new(params)
      return fail_with("VALIDATION_ERROR", "Invalid booking request", errors: form.errors.to_hash) unless form.valid?

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

      attempt = 0
      result = @placement.call(vehicle:, service_type:, dealership:, starts_at: form.starts_at) do |assignment, interval|
        backoff(attempt)
        attempt += 1
        Appointment.build_confirmed(
          customer:, vehicle:, service_type:, dealership:,
          technician_id: assignment.technician_id,
          service_bay_id: assignment.bay_id,
          start_at: interval.starts_at,
          end_at: interval.ends_at
        ).tap(&:save!)
      end
      Events.publish(Events::CONFIRMED, result.value!, occurred_at: @clock.now) if result.success?
      result
    end

    def backoff(attempt)
      return if attempt.zero?

      delay = [ BACKOFF_BASE_SECONDS * (2**(attempt - 1)), BACKOFF_CAP_SECONDS ].min
      @sleeper.call(delay * @jitter.call)
    end

    def not_found(resource, field)
      fail_with("NOT_FOUND", "#{resource} not found", errors: { field => [ "not found" ] })
    end

    def fail_with(code, detail, errors: nil, extra: nil)
      Failure([ code, { detail:, errors:, extra: } ])
    end
  end
end
