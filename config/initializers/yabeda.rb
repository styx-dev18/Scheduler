Yabeda.configure do
  counter :booking_attempts_total, comment: "Booking attempts that reached the booking service"
  counter :booking_success_total, comment: "Bookings that were confirmed"
  counter :booking_failure_total, tags: %i[reason], comment: "Bookings that failed, by error catalogue code"
  histogram :booking_duration_seconds, comment: "Booking service duration",
            buckets: [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5 ]
  histogram :availability_query_duration_seconds, comment: "Availability query duration",
            buckets: [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5 ]
end

ActiveSupport::Notifications.subscribe("booking.scheduler") do |event|
  Yabeda.booking_attempts_total.increment({})
  Yabeda.booking_duration_seconds.measure({}, event.duration / 1000.0)
  reason = event.payload[:failure_code]
  if reason
    Yabeda.booking_failure_total.increment({ reason: reason })
  else
    Yabeda.booking_success_total.increment({})
  end
end

ActiveSupport::Notifications.subscribe("availability.scheduler") do |event|
  Yabeda.availability_query_duration_seconds.measure({}, event.duration / 1000.0)
end
