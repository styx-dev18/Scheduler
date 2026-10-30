module Appointments
  class ChangeStatus
    include Dry::Monads[:result]

    TARGETS = { "in_progress" => :start!, "completed" => :complete!, "no_show" => :mark_no_show! }.freeze

    def initialize(clock: Clock)
      @clock = clock
    end

    def call(appointment_id:, status:, actor: "staff")
      unless TARGETS.key?(status)
        return fail_with("VALIDATION_ERROR", "Invalid status", errors: { "status" => [ "is not included in the list" ] })
      end

      appointment = Appointment.find_by(id: appointment_id)
      return fail_with("APPOINTMENT_NOT_FOUND", "Appointment not found") unless appointment

      ApplicationRecord.transaction { change(appointment, status, actor) }
    end

    private

    def change(appointment, status, actor)
      appointment.lock!
      now = @clock.now
      from = appointment.status

      unless Scheduling::StatusMachine.allowed?(from:, to: status)
        return invalid_transition(appointment, "Cannot move from #{from} to #{status}")
      end

      if status == "no_show" && now < appointment.start_at
        return invalid_transition(appointment, "No-show can only be recorded after the start time")
      end

      appointment.public_send(TARGETS.fetch(status), at: now, actor:)
      Events.publish(Events::STATUS_CHANGED, appointment, occurred_at: now, from_status: from, to_status: status)
      Success(appointment)
    end

    def invalid_transition(appointment, detail)
      fail_with(
        "INVALID_STATUS_TRANSITION", detail,
        extra: { allowed_transitions: Scheduling::StatusMachine.allowed_from(appointment.status) }
      )
    end

    def fail_with(code, detail, errors: nil, extra: nil)
      Failure([ code, { detail:, errors:, extra: } ])
    end
  end
end
