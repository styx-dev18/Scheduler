module ErrorCatalogue
  Entry = Struct.new(:code, :status, :title, keyword_init: true)

  ENTRIES = {
    "VALIDATION_ERROR" => Entry.new(code: "VALIDATION_ERROR", status: 422, title: "Validation failed"),
    "NOT_FOUND" => Entry.new(code: "NOT_FOUND", status: 404, title: "Resource not found"),
    "CONCURRENT_MODIFICATION" => Entry.new(code: "CONCURRENT_MODIFICATION", status: 409, title: "Concurrent modification"),
    "INTERNAL_ERROR" => Entry.new(code: "INTERNAL_ERROR", status: 500, title: "Internal server error"),
    "START_TIME_IN_PAST" => Entry.new(code: "START_TIME_IN_PAST", status: 422, title: "Start time is in the past"),
    "START_TIME_NOT_ON_SLOT_GRID" => Entry.new(code: "START_TIME_NOT_ON_SLOT_GRID", status: 422, title: "Start time is not on the slot grid"),
    "VEHICLE_OWNERSHIP_MISMATCH" => Entry.new(code: "VEHICLE_OWNERSHIP_MISMATCH", status: 422, title: "Vehicle ownership mismatch"),
    "OUTSIDE_OPENING_HOURS" => Entry.new(code: "OUTSIDE_OPENING_HOURS", status: 422, title: "Outside opening hours"),
    "DEALERSHIP_CLOSED" => Entry.new(code: "DEALERSHIP_CLOSED", status: 422, title: "Dealership closed"),
    "VEHICLE_ALREADY_BOOKED" => Entry.new(code: "VEHICLE_ALREADY_BOOKED", status: 409, title: "Vehicle already booked"),
    "NO_BAY" => Entry.new(code: "NO_BAY", status: 409, title: "No service bay available"),
    "NO_TECHNICIAN" => Entry.new(code: "NO_TECHNICIAN", status: 409, title: "No technician available"),
    "NO_CAPACITY" => Entry.new(code: "NO_CAPACITY", status: 409, title: "No capacity available"),
    "IDEMPOTENCY_KEY_REUSED" => Entry.new(code: "IDEMPOTENCY_KEY_REUSED", status: 422, title: "Idempotency key reused"),
    "IDEMPOTENCY_KEY_IN_PROGRESS" => Entry.new(code: "IDEMPOTENCY_KEY_IN_PROGRESS", status: 409, title: "Idempotency key in progress")
  }.freeze

  def self.fetch(code)
    ENTRIES[code.to_s]
  end
end
