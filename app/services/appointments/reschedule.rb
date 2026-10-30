module Appointments
  class Reschedule
    include Dry::Monads[:result]

    def initialize(clock: Clock, placement: Appointments::Placement.new(clock:))
      @clock = clock
      @placement = placement
    end

    def call(appointment_id:, params:, actor: "customer")
      form = RescheduleRequest.new(params)
      return fail_with("VALIDATION_ERROR", "Invalid reschedule request", errors: form.errors.to_hash) unless form.valid?

      appointment = Appointment.find_by(id: appointment_id)
      return fail_with("APPOINTMENT_NOT_FOUND", "Appointment not found") unless appointment

      ApplicationRecord.transaction { reschedule(appointment, form, actor) }
    end

    private

    def reschedule(appointment, form, actor)
      appointment.lock!

      expected = form.expected_lock_version
      if expected && expected != appointment.lock_version
        return fail_with("CONCURRENT_MODIFICATION", "The appointment was modified by another request")
      end

      unless appointment.confirmed?
        return fail_with("INVALID_STATUS_TRANSITION", "Only confirmed appointments can be rescheduled",
                         extra: { allowed_transitions: Scheduling::StatusMachine.allowed_from(appointment.status) })
      end

      previous_start_at = appointment.start_at
      previous_end_at = appointment.end_at
      previous_technician_id = appointment.technician_id
      previous_bay_id = appointment.service_bay_id

      result = @placement.call(
        vehicle: appointment.vehicle,
        service_type: appointment.service_type,
        dealership: appointment.dealership,
        starts_at: form.starts_at,
        exclude_appointment_id: appointment.id,
        preferred: Scheduling::Assignment.new(bay_id: previous_bay_id, technician_id: previous_technician_id)
      ) do |assignment, interval|
        appointment.update!(
          start_at: interval.starts_at,
          end_at: interval.ends_at,
          technician_id: assignment.technician_id,
          service_bay_id: assignment.bay_id
        )
        appointment.reschedules.create!(
          prev_start_at: previous_start_at,
          prev_end_at: previous_end_at,
          new_start_at: interval.starts_at,
          new_end_at: interval.ends_at,
          actor:,
          request_id: Current.request_id
        )
        appointment
      end

      if result.success?
        Events.publish(
          Events::RESCHEDULED, result.value!, occurred_at: @clock.now,
          previous_start_at:, previous_end_at:,
          technician_id: appointment.technician_id, service_bay_id: appointment.service_bay_id
        )
      end
      result
    end

    def fail_with(code, detail, errors: nil, extra: nil)
      Failure([ code, { detail:, errors:, extra: } ])
    end
  end
end
