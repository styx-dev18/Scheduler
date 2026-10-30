module ErrorCatalogue
  Entry = Struct.new(:code, :status, :title, :example, keyword_init: true)

  ENTRIES = {
    "VALIDATION_ERROR" => Entry.new(code: "VALIDATION_ERROR", status: 422, title: "Validation failed", example: "A required field is missing or malformed in the request body."),
    "NOT_FOUND" => Entry.new(code: "NOT_FOUND", status: 404, title: "Resource not found", example: "The referenced customer, vehicle, service type or dealership does not exist."),
    "APPOINTMENT_NOT_FOUND" => Entry.new(code: "APPOINTMENT_NOT_FOUND", status: 404, title: "Appointment not found", example: "GET /api/v1/appointments/{id} with an id that does not exist."),
    "CONCURRENT_MODIFICATION" => Entry.new(code: "CONCURRENT_MODIFICATION", status: 409, title: "Concurrent modification", example: "Two requests update the same appointment at the same moment."),
    "INTERNAL_ERROR" => Entry.new(code: "INTERNAL_ERROR", status: 500, title: "Internal server error", example: "An unexpected failure occurred while processing the request."),
    "START_TIME_IN_PAST" => Entry.new(code: "START_TIME_IN_PAST", status: 422, title: "Start time is in the past", example: "Booking with a start time earlier than the current time."),
    "START_TIME_NOT_ON_SLOT_GRID" => Entry.new(code: "START_TIME_NOT_ON_SLOT_GRID", status: 422, title: "Start time is not on the slot grid", example: "Booking at 09:10 when slots start every 30 minutes."),
    "VEHICLE_OWNERSHIP_MISMATCH" => Entry.new(code: "VEHICLE_OWNERSHIP_MISMATCH", status: 422, title: "Vehicle ownership mismatch", example: "The vehicle does not belong to the given customer."),
    "OUTSIDE_OPENING_HOURS" => Entry.new(code: "OUTSIDE_OPENING_HOURS", status: 422, title: "Outside opening hours", example: "Booking a 2 hour service starting 17:00 at a dealership that closes at 18:00."),
    "DEALERSHIP_CLOSED" => Entry.new(code: "DEALERSHIP_CLOSED", status: 422, title: "Dealership closed", example: "Booking on a Sunday when the dealership is closed."),
    "VEHICLE_ALREADY_BOOKED" => Entry.new(code: "VEHICLE_ALREADY_BOOKED", status: 409, title: "Vehicle already booked", example: "The vehicle already has an appointment overlapping the requested time."),
    "NO_BAY" => Entry.new(code: "NO_BAY", status: 409, title: "No service bay available", example: "Every service bay is occupied during the requested interval."),
    "NO_TECHNICIAN" => Entry.new(code: "NO_TECHNICIAN", status: 409, title: "No technician available", example: "No qualified technician is free for the whole requested interval."),
    "NO_CAPACITY" => Entry.new(code: "NO_CAPACITY", status: 409, title: "No capacity available", example: "No bay and technician pair is free for the requested interval."),
    "IDEMPOTENCY_KEY_REUSED" => Entry.new(code: "IDEMPOTENCY_KEY_REUSED", status: 422, title: "Idempotency key reused", example: "The same Idempotency-Key is sent with a different request body."),
    "IDEMPOTENCY_KEY_IN_PROGRESS" => Entry.new(code: "IDEMPOTENCY_KEY_IN_PROGRESS", status: 409, title: "Idempotency key in progress", example: "A request with the same Idempotency-Key is still being processed."),
    "INVALID_STATUS_TRANSITION" => Entry.new(code: "INVALID_STATUS_TRANSITION", status: 409, title: "Invalid status transition", example: "Confirming an appointment that is already cancelled."),
    "CANCELLATION_WINDOW_CLOSED" => Entry.new(code: "CANCELLATION_WINDOW_CLOSED", status: 422, title: "Cancellation window closed", example: "Cancelling an appointment too close to its start time."),
    "UNAUTHORIZED" => Entry.new(code: "UNAUTHORIZED", status: 401, title: "Unauthorized", example: "The metrics endpoint is called with a missing or invalid bearer token."),
    "RATE_LIMITED" => Entry.new(code: "RATE_LIMITED", status: 429, title: "Too many requests", example: "More requests than the per-client limit within the throttle window."),
    "REQUEST_TIMEOUT" => Entry.new(code: "REQUEST_TIMEOUT", status: 504, title: "Request timed out", example: "The request exceeded the server-side time limit."),
    "SERVICE_UNAVAILABLE" => Entry.new(code: "SERVICE_UNAVAILABLE", status: 503, title: "Service unavailable", example: "A dependency such as the database is temporarily unreachable.")
  }.freeze

  def self.fetch(code)
    ENTRIES[code.to_s]
  end
end
