module Appointments
  module Events
    CONFIRMED = "appointment.confirmed".freeze
    RESCHEDULED = "appointment.rescheduled".freeze
    CANCELLED = "appointment.cancelled".freeze
    STATUS_CHANGED = "appointment.status_changed".freeze

    def self.publish(name, appointment, occurred_at:, **extra)
      payload = {
        appointment_id: appointment.id,
        customer_id: appointment.customer_id,
        dealership_id: appointment.dealership_id,
        status: appointment.status,
        start_at: appointment.start_at,
        end_at: appointment.end_at,
        occurred_at: occurred_at,
        request_id: Current.request_id,
        **extra
      }
      ActiveRecord.after_all_transactions_commit { ActiveSupport::Notifications.instrument(name, payload) }
      nil
    end
  end
end
