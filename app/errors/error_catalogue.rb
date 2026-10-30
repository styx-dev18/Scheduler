module ErrorCatalogue
  Entry = Struct.new(:code, :status, :title, keyword_init: true)

  ENTRIES = {
    "VALIDATION_ERROR" => Entry.new(code: "VALIDATION_ERROR", status: 422, title: "Validation failed"),
    "NOT_FOUND" => Entry.new(code: "NOT_FOUND", status: 404, title: "Resource not found"),
    "CONCURRENT_MODIFICATION" => Entry.new(code: "CONCURRENT_MODIFICATION", status: 409, title: "Concurrent modification"),
    "INTERNAL_ERROR" => Entry.new(code: "INTERNAL_ERROR", status: 500, title: "Internal server error")
  }.freeze

  def self.fetch(code)
    ENTRIES[code.to_s]
  end
end
