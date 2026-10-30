module Appointments
  class Cancel
    include Dry::Monads[:result]

    def initialize(clock: Clock, cutoff_hours: Integer(ENV.fetch("CANCELLATION_CUTOFF_HOURS", "0")))
      @clock = clock
      @cutoff_hours = cutoff_hours
    end

    def call(appointment_id:, reason: nil, actor: "customer")
      unless reason.nil? || reason.is_a?(String)
        return fail_with("VALIDATION_ERROR", "Invalid cancellation request", errors: { "reason" => [ "must be a string" ] })
      end

      if reason && reason.length > Appointment::MAX_REASON_LENGTH
        message = "is too long (maximum is #{Appointment::MAX_REASON_LENGTH} characters)"
        return fail_with("VALIDATION_ERROR", "Invalid cancellation request", errors: { "reason" => [ message ] })
      end

      appointment = Appointment.find_by(id: appointment_id)
      return fail_with("APPOINTMENT_NOT_FOUND", "Appointment not found") unless appointment

      ApplicationRecord.transaction { cancel_locked(appointment, reason, actor) }
    end

    private

    def cancel_locked(appointment, reason, actor)
      appointment.lock!
      return Success(appointment) if appointment.cancelled?

      allowed = Scheduling::StatusMachine.allowed_from(appointment.status)
      unless allowed.include?("cancelled")
        return fail_with("INVALID_STATUS_TRANSITION", "Appointment cannot be cancelled",
                         extra: { allowed_transitions: allowed })
      end

      now = @clock.now
      if @cutoff_hours.positive? && appointment.start_at - now < @cutoff_hours.hours
        return fail_with("CANCELLATION_WINDOW_CLOSED", "Cancellation window closed")
      end

      appointment.cancel!(at: now, actor:, reason:)
      Events.publish(Events::CANCELLED, appointment, occurred_at: now, cancelled_at: now, reason:)
      Success(appointment)
    end

    def fail_with(code, detail, errors: nil, extra: nil)
      Failure([ code, { detail:, errors:, extra: } ])
    end
  end
end
